**语言：** [English](../ginkgo-android-gsi.md) | 简体中文

# Redmi Note 8 (ginkgo) 主线内核 Android GSI 支持

> 设备：Xiaomi Redmi Note 8 · codename **ginkgo** · SoC **SM6125 (trinket)** · 序列号 `<serial>`
> 内核：主线 Linux 7.0，现在可以启动 **Android 17 GSI** 系统镜像
> 状态：内核侧支持已完成（config + boot.img 工具链），真机验证待进行
> 前置：现有主线 Ubuntu 适配（显示、触控、Wi-Fi、Docker）已经能编译并启动。

**关联文档 / 文件**

| 文档 / 文件 | 内容 |
|------------|------|
| [ginkgo-mainline-bringup-chronicle.md](./ginkgo-mainline-bringup-chronicle.md) | 全机时间线 |
| [mainline-ginkgo-porting-guide.md](./mainline-ginkgo-porting-guide.md) | 硬件清单与差距 |
| [flash-guide.md](./flash-guide.md) | 刷主线 boot.img |
| [backup/ginkgo/README.md](../../backup/ginkgo/README.md) | LineageOS 17.1 分区备份 |
| [restore-android.sh](../../scripts/restore-android.sh) | 刷回原厂 boot（应急出口） |
| [ginkgo.fragment](../../config/ginkgo.fragment) | Ubuntu 编译 fragment |
| [ginkgo-android.fragment](../../config/ginkgo-android.fragment) | **Android GSI 编译 fragment（本次工作）** |
| [build-bootimg-android.sh](../../scripts/build-bootimg-android.sh) | **打包 Android boot.img（本次工作）** |

---

## 0. 一句话结论

ginkgo **没有 `super` 分区**（见 `backup/ginkgo/partitions.txt`：`system` 和 `vendor` 都是真实 eMMC 分区），所以 GSI 的启动方式和 LineageOS 完全一样：`boot.img` 里放内核 + DTB + 一阶段 ramdisk，GSI 刷到 `system`。主线内核获得 Android 支持靠两件事：(a) 合并新的内核 config fragment（binder、SELinux、f2fs/erofs、FBE 加密、bootconfig、uclamp……）；(b) 重新打包 `boot.img`——主线内核 + DTB **加上 LineageOS 的一阶段 ramdisk**，让 Android init 能挂载 `system`/`vendor`。eMMC 分区布局不用动。

---

## 1. 「Android 支持」在这里指什么

Android 用户态需要一批 Ubuntu 编译没开的内核设施：

| 领域 | 原因 | fragment 条目 |
|------|------|---------------|
| Binder IPC | Android 服务之间全部靠 binder | `CONFIG_ANDROID`、`CONFIG_ANDROID_BINDER_IPC`、`CONFIG_ANDROID_BINDERFS`、`CONFIG_MEMFD_CREATE` |
| SELinux | Android init 强制执行策略（先 permissive 启动） | `CONFIG_SECURITY_SELINUX*` |
| 文件系统 | GSI system = erofs，userdata = f2fs（Android 17 格式化） | `CONFIG_EROFS_FS`、`CONFIG_F2FS_FS`、`CONFIG_SQUASHFS`、`CONFIG_EXT4_FS_SECURITY` |
| 文件加密 | userdata 的 FBE + 元数据加密，APEX 用 fs-verity | `CONFIG_FS_ENCRYPTION`、`CONFIG_FS_VERITY`、`CONFIG_DM_CRYPT`、`CONFIG_CRYPTO_*` |
| 启动镜像 | ramdisk 解压器、bootconfig（header v4）、devtmpfs | `CONFIG_BLK_DEV_INITRD`、`CONFIG_RD_*`、`CONFIG_BOOT_CONFIG`、`CONFIG_DEVTMPFS` |
| GKI 必需 | uclamp、PSI、cgroup BPF、system dmabuf heap、zram | `CONFIG_UCLAMP_TASK*`、`CONFIG_PSI`、`CONFIG_CGROUP_BPF`、`CONFIG_DMABUF_HEAPS_SYSTEM`、`CONFIG_ZRAM` |

ashmem 早已从主线删除，现代 Android 用 `memfd_create()` 替代，所以这里什么都不用加。

Android boot 镜像**仍然是 header v2**——ginkgo bootloader 本来就认这个格式，和 Ubuntu 版 `boot.img` 的几何完全一致（kernel、ramdisk、dtb 偏移相同）。

---

## 2. 编译 Android 内核

```bash
# 和 Ubuntu 用同一个内核树；ANDROID=1 会在 ginkgo.fragment 之后再合并
# config/ginkgo-android.fragment。
ANDROID=1 ./scripts/build-kernel.sh
```

产出 `out/Image.gz` + `out/sm6125-xiaomi-ginkgo.dtb`，两个 fragment 都生效。`ANDROID=1` 可以随时开关；不开时只合并原 fragment 并重新编译。

## 3. 打包 Android boot 镜像

```bash
./scripts/build-bootimg-android.sh
```

脚本复刻 **小米 system-as-root 方案**（ginkgo 所有 ROM 都这么干——原厂 boot 镜像的 ramdisk 是 0 字节）：

1. 从 `backup/ginkgo/cmdline.txt`（本机自己的 cmdline，`root=PARTUUID=54dc1022-…`）读出 **system 的 PARTUUID**——ginkgo 的内核直接把它当根文件系统挂载。
2. 打包 `out/boot-android.img`（header v2）：**主线内核 + 主线 DTB**、**无 ramdisk**（ramdisk_size = 0），cmdline 为 `androidboot.hardware=qcom androidboot.bootdevice=4744000.sdhci androidboot.selinux=permissive … root=PARTUUID=<system> skip_initramfs rootwait ro init=/init`。
3. PARTUUID 标识的是 `system` 这个**分区**——往里面刷 GSI 也不会变。

可用 `SYSTEM_PARTUUID=<uuid>` 覆盖。LineageOS 风格的启动（确实带一阶段 ramdisk + fstab）用 `RAMDISK_ANDROID=/path/ramdisk.cpio.gz`，脚本会自动去掉 `root=`/`skip_initramfs`，交给一阶段 init 挂 system。`ANDROID_ADD_FW=1` 可把 ginkgo GPU 固件 cpio 追加进该 ramdisk。

## 3b. 修补 vendor fstab（HyperOS 2 / Android 15 vendor 必需）

HyperOS 2 vendor 给 `/data` 和 `/metadata` 打了 `wrappedkey` + `inlinecrypt` 标记——这是硬件 wrapped key / 内联加密，需要高通 ICE，主线内核没有实现。一阶段 init 挂不上 `/data`，GSI 就永远起不来。去掉这些标记，Android 就会退回软件 FBE（fscrypt + dm-crypt，主线内核都已内置）：

```bash
./scripts/patch-vendor-fstab.sh path/to/vendor.img /tmp/vendor-patched.img
# 然后：
fastboot flash vendor /tmp/vendor-patched.img
```

脚本用 `debugfs` 改副本（不需要 root）：去掉 `wrappedkey`、`inlinecrypt`，并把 sdhci sysfs 路径从下流内核的 `4784000.sdhci` 改成主线的 `4744000.sdhci`。

## 4. 刷机顺序

```bash
export PATH="$HOME/.local/bin:$PATH"

# 0. 先备份需要的东西。这步会把 Ubuntu 从 userdata 抹掉：
#    之后想恢复可以重新刷 fastboot flash userdata out/rootfs.ext4。

# 1. 刷修补过 fstab 的 HyperOS 2 vendor（只改了 fstab，其余原样）：
fastboot flash vendor /tmp/vendor-patched.img

# 2. 主线内核，无 ramdisk（小米 SAR 方案）
fastboot flash boot out/boot-android.img

# 3. GSI system 镜像（Android 17 arm64，Google GSI 页面下载）
#    如果镜像比 system 分区大，先 erase。
fastboot erase system
fastboot flash system gsi_arm64_ab.img

# 4. 关闭 verified boot（vbmeta 不在本仓库，保留你的备份）
fastboot flash vbmeta --disable-verification backup/ginkgo/vbmeta.img

# 5. 清空 userdata——Android 17 会格式化成 f2fs + FBE
fastboot -w

# 6. 重启并盯 ttyMSM0
fastboot reboot
```

## 5. 预期结果

- **首次启动**：cmdline 里写死了 `androidboot.selinux=permissive`，GSI 在没有策略文件时也能起来。首次启动会比较久（FBE 密钥初始化、f2fs 格式化、dex2oat）。
- **adb**：DWC3 functionfs + `androidboot.configfs=true` 已在 cmdline 里；用户态起来后 `adb devices` 应该能看到设备。
- **已知主线缺口（不可用）**：相机、音频、RIL/基带、GPS。显示、触控、GPU 应该正常——DRM/DSI、NT36672A、Adreno 610 驱动都已在这个内核里。
- **Wi-Fi**：内核的固件请求路径（`/lib/firmware`）不会去翻 Android 的 `/vendor/firmware`，所以 Android 下 WCN3990 可能起不来。如果需要，用 `CONFIG_EXTRA_FIRMWARE` 把固件编进内核（和触控屏同一个机制）。

## 6. 已知坑

1. **HyperOS 2 vendor（Android 15，`~/Desktop/VENDOR_WORK/vendor.img`）**满足 GSI 对 vendor（Android 11+）的要求，Android 17 GSI 应该能通过 vendor 兼容性检查。但必须先按 §3b 修补 fstab 再刷——原版 fstab 的 `wrappedkey`/`inlinecrypt` 依赖高通 ICE 硬件，主线没有。实验前请备份好原版 `vendor.img`、`boot.img`、`vbmeta.img`、`dtbo.img`。
2. **`fastboot -w` 之后 Ubuntu 就没了**：Ubuntu rootfs 在 `userdata` 上。想回去就重刷 `out/rootfs.ext4` 和 Ubuntu 版 `boot.img`（见 `README.md` 刷机顺序）。`restore-android.sh` 则把手机还原成原厂 Android。
3. **`boot-android.img` 不会启动 Ubuntu rootfs**：它带的是 Android cmdline（`root=PARTUUID` 指向 `system`、`init=/init`），别拿它去覆盖正在用的 Ubuntu 系统。
4. **ramoops 已启用**（主线 DTB 里）：GSI 启动失败后，`fastboot flash boot backup/ginkgo/boot.img` 刷回 LineageOS，再用 `./scripts/capture-logs.sh` 抓 pstore（和 Ubuntu 适配时同一套流程）。
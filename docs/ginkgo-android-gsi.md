**Language:** English | [简体中文](zh-CN/ginkgo-android-gsi.md)

# Redmi Note 8 (ginkgo) mainline kernel Android GSI support

> Device: Xiaomi Redmi Note 8 · codename **ginkgo** · SoC **SM6125 (trinket)** · serial `<serial>`
> Kernel: mainline Linux 7.0, now able to boot an **Android 17 GSI** system image
> Status: kernel-side support landed (config + boot.img tooling), on-device validation pending
> Prerequisites: the existing mainline Ubuntu bring-up (display, touch, Wi-Fi, Docker) must already build and boot.

**Related docs / files**

| Doc / file | Content |
|------------|---------|
| [ginkgo-mainline-bringup-chronicle.md](./ginkgo-mainline-bringup-chronicle.md) | Full-device timeline |
| [mainline-ginkgo-porting-guide.md](./mainline-ginkgo-porting-guide.md) | Hardware map and gaps |
| [flash-guide.md](./flash-guide.md) | Flashing a mainline boot.img |
| [backup/ginkgo/README.md](../backup/ginkgo/README.md) | LineageOS 17.1 partition backup |
| [restore-android.sh](../scripts/restore-android.sh) | Flash the stock boot back (emergency exit) |
| [ginkgo.fragment](../config/ginkgo.fragment) | Ubuntu build fragment |
| [ginkgo-android.fragment](../config/ginkgo-android.fragment) | **Android GSI build fragment (this work)** |
| [build-bootimg-android.sh](../scripts/build-bootimg-android.sh) | **Pack the Android boot.img (this work)** |

---

## 0. One-sentence conclusion

Ginkgo has **no `super` partition** (see `backup/ginkgo/partitions.txt`: `system` and `vendor` are real eMMC partitions), so a GSI boots exactly like LineageOS does: kernel + DTB + first-stage ramdisk in `boot.img`, then the GSI flashed to `system`. The mainline kernel gets Android support by (a) merging a new kernel config fragment (binder, SELinux, f2fs/erofs, FBE crypto, bootconfig, uclamp…) and (b) repacking `boot.img` with the mainline kernel + DTB **and the LineageOS first-stage ramdisk** so Android's init can mount `system`/`vendor`. Nothing on the eMMC layout needs to change.

---

## 1. What "Android support" means here

Android user space needs a handful of kernel facilities that the Ubuntu build did not enable:

| Area | Why | Fragment entries |
|------|-----|------------------|
| Binder IPC | every IPC between Android services | `CONFIG_ANDROID`, `CONFIG_ANDROID_BINDER_IPC`, `CONFIG_ANDROID_BINDERFS`, `CONFIG_MEMFD_CREATE` |
| SELinux | Android init enforces policy (boot permissive first) | `CONFIG_SECURITY_SELINUX*` |
| Filesystems | GSI system = erofs, userdata = f2fs (formatted by Android 17) | `CONFIG_EROFS_FS`, `CONFIG_F2FS_FS`, `CONFIG_SQUASHFS`, `CONFIG_EXT4_FS_SECURITY` |
| File-based encryption | FBE + metadata encryption on userdata, fs-verity for APEX | `CONFIG_FS_ENCRYPTION`, `CONFIG_FS_VERITY`, `CONFIG_DM_CRYPT`, `CONFIG_CRYPTO_*` |
| Boot image support | ramdisk decompressors, bootconfig (header v4), devtmpfs | `CONFIG_BLK_DEV_INITRD`, `CONFIG_RD_*`, `CONFIG_BOOT_CONFIG`, `CONFIG_DEVTMPFS` |
| GKI-required | uclamp, PSI, cgroup BPF, system dmabuf heap, zram | `CONFIG_UCLAMP_TASK*`, `CONFIG_PSI`, `CONFIG_CGROUP_BPF`, `CONFIG_DMABUF_HEAPS_SYSTEM`, `CONFIG_ZRAM` |

ashmem is gone from mainline (removed years ago); modern Android uses `memfd_create()` instead, so nothing is needed there.

The Android boot image itself stays **header v2**, the format the ginkgo bootloader already accepts — same `boot.img` geometry as the Ubuntu build (kernel, ramdisk, dtb offsets identical).

---

## 2. Build the Android kernel

```bash
# Same kernel tree as the Ubuntu build; ANDROID=1 additionally merges
# config/ginkgo-android.fragment after config/ginkgo.fragment.
ANDROID=1 ./scripts/build-kernel.sh
```

This produces `out/Image.gz` + `out/sm6125-xiaomi-ginkgo.dtb` with both fragments applied. You can flip `ANDROID=1` on and off freely; a subsequent build without it just merges the smaller fragment and rebuilds.

## 3. Pack the Android boot image

```bash
./scripts/build-bootimg-android.sh
```

The script reproduces the **Xiaomi system-as-root scheme** (this is what every ginkgo ROM uses — the stock boot images have a 0-byte ramdisk):

1. Reads the **system PARTUUID** from `backup/ginkgo/cmdline.txt` (the device's own cmdline, `root=PARTUUID=54dc1022-…`), where ginkgo's kernel mounts the `system` partition directly as the root filesystem.
2. Packs `out/boot-android.img` as header v2: **mainline kernel + mainline DTB**, **no ramdisk** (ramdisk_size = 0), cmdline `androidboot.hardware=qcom androidboot.bootdevice=4744000.sdhci androidboot.selinux=permissive … root=PARTUUID=<system> skip_initramfs rootwait ro init=/init`.
3. The PARTUUID identifies the `system` *partition* — it does not change when a GSI is flashed into it.
4. Applies the **Android fstab DT overlay** (`dts/ginkgo-android-fstab.dts`) to the DTB: stock ginkgo DTBs carry a `firmware/android/fstab` node that first-stage init uses to mount `vendor` — mainline DTBs do not, so without this overlay Android never boots. The overlay uses the eMMC path (`4744000.sdhci`; the stock trinket reference DTB wrongly points at UFS).

`SYSTEM_PARTUUID=<uuid>` overrides the default. For LineageOS-style boots (which DO ship a first-stage ramdisk + fstab), set `RAMDISK_ANDROID=/path/ramdisk.cpio.gz`; the script then drops `root=`/`skip_initramfs` and lets first-stage init mount system. `ANDROID_ADD_FW=1` appends the ginkgo GPU firmware cpio to that ramdisk.

## 3b. Patch the vendor fstab (needed for HyperOS 2 / Android 15 vendor)

The HyperOS 2 vendor marks `/data` and `/metadata` with `wrappedkey` + `inlinecrypt` — hardware-wrapped-key and inline-crypto flags that need Qualcomm ICE, which mainline does not implement. First-stage init would fail to mount `/data` and the GSI would never boot. Strip the flags so Android falls back to software FBE (fscrypt + dm-crypt, both built into the mainline kernel):

```bash
./scripts/patch-vendor-fstab.sh path/to/vendor.img /tmp/vendor-patched.img
# then:
fastboot flash vendor /tmp/vendor-patched.img
```

The script edits a copy via `debugfs` (no root needed): removes `wrappedkey`, `inlinecrypt` and fixes the sdhci sysfs path from the downstream `4784000.sdhci` to mainline `4744000.sdhci`.

## 4. Flash order

```bash
export PATH="$HOME/.local/bin:$PATH"

# 0. Backup what you need. This wipes Ubuntu off userdata:
#    fastboot flash userdata out/rootfs.ext4 can be re-run later to get it back.

# 1. HyperOS 2 vendor with the patched fstab (keeps your stock kernel, not needed)
#    — only the fstab was changed; flash over the installed vendor:
fastboot flash vendor /tmp/vendor-patched.img

# 2. Mainline kernel, no ramdisk (Xiaomi SAR scheme)
fastboot flash boot out/boot-android.img

# 3. GSI system image (Android 17 arm64, e.g. from Google's GSI page)
#    If the image is bigger than the system partition, erase first.
fastboot erase system
fastboot flash system gsi_arm64_ab.img

# 4. Disable verified boot (vbmeta is NOT in this repo, keep your backup)
fastboot flash vbmeta --disable-verification backup/ginkgo/vbmeta.img

# 5. Wipe userdata — Android 17 will format it f2fs + FBE
fastboot -w

# 6. Reboot and watch ttyMSM0
fastboot reboot
```

## 5. What to expect

- **First boot**: `androidboot.selinux=permissive` is baked into the cmdline, so the GSI boots without a working policy. Expect a fairly long first boot (FBE key setup, f2fs format, dex2oat).
- **adb**: DWC3 functionfs + `androidboot.configfs=true` are already in the cmdline; `adb devices` should show the device once userspace is up.
- **Not working (known mainline gaps)**: camera, audio, RIL/modem, GPS. Display, touch, and GPU should work — DRM/DSI, NT36672A and the Adreno 610 driver are already in this kernel.
- **Wi-Fi**: kernel firmware requests (`/lib/firmware`) do not look into Android's `/vendor/firmware`, so WCN3990 may not come up under Android. If it matters, build the firmware into the kernel via `CONFIG_EXTRA_FIRMWARE` (same mechanism the touch panel uses).

## 6. Known caveats

1. **The HyperOS 2 vendor (Android 15, `~/Desktop/VENDOR_WORK/vendor.img`)** satisfies the GSI vendor requirement (Android 11+), so the Android 17 GSI should pass the vendor compatibility check. It must be flashed with the fstab patch (§3b) — the stock fstab's `wrappedkey`/`inlinecrypt` flags require Qualcomm ICE hardware support that mainline does not provide. Also back up the original `vendor.img`, `boot.img`, `vbmeta.img`, `dtbo.img` before experimenting.
2. **Ubuntu is gone after `fastboot -w`**: the Ubuntu rootfs lives on `userdata`. Re-flash `out/rootfs.ext4` and the Ubuntu `boot.img` to go back (see `README.md` flash order). `restore-android.sh` returns the phone to stock Android.
3. **`boot-android.img` does not mount the Ubuntu rootfs**: it carries the Android cmdline (`root=PARTUUID` of `system`, `init=/init`); do not flash it over a working Ubuntu install expecting it to boot Ubuntu.
4. **ramoops is enabled** in the mainline DTB — after a failed GSI boot, flash the stock boot back and read pstore logs with `./scripts/capture-logs.sh` (same workflow as the Ubuntu bring-up).
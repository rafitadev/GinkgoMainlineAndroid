**语言：** [English](README.md) | 简体中文

# ginkgo 移植参考资料

从 ReGinkgo 树、LineageOS 17.1 下游内核和主线内核收集，供 mainline 适配对照使用。

## 目录结构

```
reference/
├── mainline/          # 主线 kernel 现有 ginkgo DTS（来自 torvalds/linux）
│   ├── sm6125-ginkgo.dts
│   ├── sm6125-ginkgo-common.dtsi
│   ├── sm6125.dtsi
│   └── sm6115-wifi-ref.dtsi   # WiFi 节点参考（sm6115 已有）
└── downstream/        # ReGinkgo（4.14.356，rafitadev）+ LineageOS 17.1
    ├── dts/xiaomi/ginkgo/     # LineageOS 17.1 完整 ginkgo 设备树
    │   ├── display/dsi-panel-nt36672a-tianma-fhd-video.dtsi  ← 面板时序/init
    │   ├── ginkgo-trinket-touchscreen.dtsi                   ← SPI 触控节点
    │   ├── ginkgo-trinket-display.dtsi
    │   ├── ginkgo-trinket-pinctrl.dtsi
    │   └── ...
    ├── dts/qcom/              # ReGinkgo trinket 平台 DTS（89 个文件，含全部变体）
    ├── dt-bindings/           # ReGinkgo include/dt-bindings 头文件（411 个）
    ├── configs/               # ReGinkgo Android 配置：ginkgo.config、ginkgo-stock_defconfig、
    │   │                      #   xiaomi-trinket.config、trinket[_-perf]_defconfig、ksu/rksu/sukisu.config
    │   └── vendor/            # Qualcomm vendor defconfig
    ├── configs/gki/           # GKI 基础 fragment（android-base-arm64.cfg 等）
    ├── build/                 # ReGinkgo build.config.* 与构建脚本（build.sh、do_build.sh 等）
    └── drivers/
        ├── nt36xxx_spi_c3j/     # Novatek SPI 触控驱动（已移植到主线 linux/drivers/input/touchscreen/nt36xxx/）
        └── dsi-staging/         # 下游 DSI 面板驱动（init 序列解析参考）
```

## 来源

| 内容 | 仓库 | 分支 |
|------|------|------|
| ReGinkgo DTS / dt-bindings / configs / build | [rafitadev/ReGinkgo](https://github.com/rafitadev/ReGinkgo)（本地副本 `~/ReGinkgo`） | 4.14.356-ReGinkgo |
| LineageOS 17.1 DTS + 驱动 | [LineageOS/android_kernel_xiaomi_sm6125](https://github.com/LineageOS/android_kernel_xiaomi_sm6125) | lineage-17.1 |
| 主线 DTS | [torvalds/linux](https://github.com/torvalds/linux) | master |

克隆方式：sparse clone（`--filter=blob:none --sparse`），仅检出上述路径。

## 各子系统对照

| 子系统 | 主线参考 | 下游参考 |
|--------|----------|----------|
| 显示 | `mainline/sm6125-ginkgo-common.dtsi` | `downstream/dts/xiaomi/ginkgo/display/dsi-panel-nt36672a-tianma-fhd-video.dtsi` |
| 触控 | `linux/drivers/input/touchscreen/nt36xxx/`（已移植，2026-08-17 出点） | `downstream/drivers/nt36xxx_spi_c3j/` + `ginkgo-trinket-touchscreen.dtsi` |
| WiFi | `mainline/sm6115-wifi-ref.dtsi` | 下游 WiFi 在 qcom-base/trinket-idp.dtsi 中（ICNSS） |

## 固件

见 `firmware/ginkgo/`。WiFi 固件已从设备 `/vendor/firmware_mnt/image/` 提取（`adb root`）。

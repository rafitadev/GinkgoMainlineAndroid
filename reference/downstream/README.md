# Downstream references (ReGinkgo + LineageOS 17.1)

**Language:** English | [简体中文](../README.zh-CN.md)

Downstream kernel material for side-by-side comparison with the mainline bring-up.

## Contents

| Path | Content | Source |
|------|---------|--------|
| `dts/qcom/` | trinket platform DTS (89 files, all variants incl. iot/rumi/idp/qrd) | `~/ReGinkgo/arch/arm64/boot/dts/qcom/` (4.14.356-ReGinkgo) |
| `dt-bindings/` | downstream DT binding headers (411 files) | `~/ReGinkgo/include/dt-bindings/` |
| `configs/` | `ginkgo.config`, `ginkgo-stock_defconfig`, `xiaomi-trinket.config`, `trinket_defconfig`, `trinket-perf_defconfig`, `ksu.config`, `rksu.config`, `sukisu.config`, `crash_key.config`, `misc_debug_defconfig`, `debugfs.config`, `unified.config` | `~/ReGinkgo/arch/arm64/configs/` |
| `configs/vendor/` | Qualcomm vendor defconfigs | `~/ReGinkgo/arch/arm64/configs/vendor/` |
| `configs/gki/` | GKI base fragments (`android-base-arm64.cfg`, …) | `~/ReGinkgo/kernel/configs/` |
| `build/` | `build.config.*`, `build.sh`, `do_build.sh`, `build_reginkgo.sh`, `disable_dbgfs.sh` | `~/ReGinkgo/` |
| `dts/xiaomi/ginkgo/` | LineageOS 17.1 full ginkgo device tree | lineage-17.1 (see parent README) |
| `drivers/` | nt36xxx SPI touch + dsi-staging excerpts | lineage-17.1 (see parent README) |

## Why it is here

- `dts/qcom/trinket-*.dtsi` — the downstream platform tree for SM6125 (ginkgo's SoC): clocks, regulators, SMMU, USB, QUPV3, display pipeline. Useful to answer "what did downstream do here" while porting to mainline.
- `dt-bindings/` — the downstream binding headers referenced by those DTS files (many describe vendor-specific QCOM bindings that never hit mainline).
- `configs/ginkgo.config` + `ginkgo-stock_defconfig` — the exact Android config the device shipped with; compare with `config/ginkgo.fragment` + `config/ginkgo-android.fragment` in this repo.
- `configs/gki/` — the GKI fragments the ReGinkgo build starts from.
- `build/` — how the ReGinkgo kernel is built (GKI-style build.config flow).

Downstream excerpts keep their upstream licenses (GPL-2.0 for the kernel material). The ReGinkgo tree is GPL-2.0, authored by rafitadev.
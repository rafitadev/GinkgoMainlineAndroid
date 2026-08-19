#!/usr/bin/env bash
# Build boot-android.img for ginkgo: mainline kernel + ginkgo DTB, packed as
# Qualcomm boot image header v2 (what the ginkgo bootloader accepts). Flash
# it together with an Android GSI system image.
#
# Xiaomi ships ginkgo boot images with NO ramdisk (ramdisk_size = 0): the
# kernel mounts the system partition directly via root=PARTUUID + skip_initramfs
# (system-as-root). This script reproduces that scheme, which is what the
# current on-device vendor (HyperOS 2 / Android 15) expects.
#
# The system PARTUUID is read from backup/ginkgo/cmdline.txt (captured from
# this device). Override with SYSTEM_PARTUUID. The PARTUUID identifies the
# system *partition*; it stays the same after flashing a GSI into it.
#
# A ramdisk mode is kept for LineageOS-style boots (which DO ship a first-
# stage ramdisk + fstab): set RAMDISK_ANDROID=/path/ramdisk.cpio.gz (and the
# cmdline loses root=/skip_initramfs automatically).
#
# Usage: ./scripts/build-bootimg-android.sh
# Env:   SYSTEM_PARTUUID=<uuid>              (default: from backup cmdline.txt)
#        RAMDISK_ANDROID=/path/ramdisk.cpio.gz  (switch to ramdisk mode)
#        ANDROID_ADD_FW=1                     (append firmware cpio to ramdisk)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/env.sh
source "$ROOT/scripts/env.sh"

OUT="$ROOT/out"
KERNEL="$OUT/Image.gz"
DTB="$OUT/$DTB_NAME"
BACKUP="${BACKUP:-$ROOT/backup/ginkgo}"
BOOTIMG="$OUT/boot-android.img"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Match stock Xiaomi/LineageOS boot header (unpack_bootimg from backup)
PAGESIZE=4096
BASE=0x00000000
KERNEL_OFFSET=0x00008000
RAMDISK_OFFSET=0x01000000
SECOND_OFFSET=0x00f00000
TAGS_OFFSET=0x00000100
DTB_OFFSET=0x01f00000
HEADER_VERSION=2
OS_VERSION=10.0.0
OS_PATCH_LEVEL=2022-01

[[ -f "$KERNEL" ]] || { echo "missing $KERNEL — run scripts/build-kernel.sh first" >&2; exit 1; }
[[ -f "$DTB" ]] || { echo "missing $DTB — run scripts/build-kernel.sh first" >&2; exit 1; }
command -v mkbootimg >/dev/null || { echo "mkbootimg not found — run scripts/setup-deps.sh" >&2; exit 1; }

RAMDISK="${RAMDISK_ANDROID:-}"
BOOT_CMDLINE="console=ttyMSM0,115200n8 androidboot.console=ttyMSM0 earlycon=msm_serial_dm,0x4a90000 keep_bootcon ignore_loglevel loglevel=8 clk_ignore_unused fw_devlink.sync_state=disabled androidboot.hardware=qcom androidboot.bootdevice=4744000.sdhci androidboot.fstab_suffix=emmc androidboot.configfs=true androidboot.usbcontroller=4e00000.dwc3 androidboot.selinux=permissive androidboot.verifiedbootstate=orange loop.max_part=7 buildvariant=userdebug"

if [[ -z "$RAMDISK" ]]; then
	# --- Xiaomi SAR mode: no ramdisk, kernel mounts system directly ---
	SYSTEM_PARTUUID="${SYSTEM_PARTUUID:-}"
	if [[ -z "$SYSTEM_PARTUUID" ]]; then
		[[ -f "$BACKUP/cmdline.txt" ]] || { echo "no SYSTEM_PARTUUID and no $BACKUP/cmdline.txt" >&2; exit 1; }
		SYSTEM_PARTUUID="$(grep -o 'root=PARTUUID=[0-9a-f-]*' "$BACKUP/cmdline.txt" | head -1 | cut -d= -f3)"
		[[ -n "$SYSTEM_PARTUUID" ]] || { echo "no root=PARTUUID in $BACKUP/cmdline.txt" >&2; exit 1; }
	fi
	echo "==> Xiaomi SAR mode: no ramdisk, root=PARTUUID=$SYSTEM_PARTUUID"
	RAMDISK_FILE="$TMP/empty"
	: > "$RAMDISK_FILE"
	CMDLINE="$BOOT_CMDLINE root=PARTUUID=$SYSTEM_PARTUUID skip_initramfs rootwait ro init=/init"
else
	# --- Ramdisk mode (LineageOS-style) ---
	echo "==> Ramdisk mode: $RAMDISK"
	if [[ "${ANDROID_ADD_FW:-}" == "1" && -d "$ROOT/firmware/ginkgo/gpu" ]]; then
		echo "==> Appending ginkgo firmware cpio to the ramdisk"
		FW_STAGE="$TMP/fw-staging"
		FW_RAMDISK="$TMP/ramdisk-fw.cpio.gz"
		mkdir -p "$FW_STAGE/lib/firmware/qcom/sm6125/xiaomi/ginkgo"
		FW="$ROOT/firmware/ginkgo/gpu"
		[[ -f "$FW/a630_sqe.fw" ]] && install -m 644 "$FW/a630_sqe.fw" "$FW_STAGE/lib/firmware/qcom/"
		for f in a610_zap.mdt a610_zap.b00 a610_zap.b01 a610_zap.b02; do
			[[ -f "$FW/$f" ]] && install -m 644 "$FW/$f" "$FW_STAGE/lib/firmware/qcom/sm6125/xiaomi/ginkgo/"
		done
		( cd "$FW_STAGE" && find . -print0 | cpio --null -o --format=newc ) | gzip -9 >"$FW_RAMDISK"
		cat "$RAMDISK" "$FW_RAMDISK" >"$TMP/ramdisk-merged.cpio.gz"
		RAMDISK_FILE="$TMP/ramdisk-merged.cpio.gz"
	else
		RAMDISK_FILE="$RAMDISK"
	fi
	CMDLINE="$BOOT_CMDLINE"
fi

echo "==> Packing $BOOTIMG (header v2, mainline kernel + DTB)"
mkbootimg \
	--header_version "$HEADER_VERSION" \
	--kernel "$KERNEL" \
	--dtb "$DTB" \
	--ramdisk "$RAMDISK_FILE" \
	--cmdline "$CMDLINE" \
	--pagesize "$PAGESIZE" \
	--base "$BASE" \
	--kernel_offset "$KERNEL_OFFSET" \
	--ramdisk_offset "$RAMDISK_OFFSET" \
	--second_offset "$SECOND_OFFSET" \
	--tags_offset "$TAGS_OFFSET" \
	--dtb_offset "$DTB_OFFSET" \
	--os_version "$OS_VERSION" \
	--os_patch_level "$OS_PATCH_LEVEL" \
	-o "$BOOTIMG"

echo "==> cmdline:"
echo "    $CMDLINE"
command -v unpack_bootimg >/dev/null && unpack_bootimg --boot_img "$BOOTIMG" --out "$TMP/verify" 2>&1 | head -15
ls -lh "$BOOTIMG"
echo
echo "Flash: fastboot flash boot $BOOTIMG"
echo "Then flash a GSI system image + wipe data — see docs/ginkgo-android-gsi.md"
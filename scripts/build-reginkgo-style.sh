#!/usr/bin/env bash
# Build the ginkgo MAINLINE kernel (Linux 7.0) and pack a flashable
# AnyKernel3 zip, mirroring the ReGinkgo (build_reginkgo.sh) flow:
#   defconfig + fragments -> clang build -> Image.gz-dtb + dtb + dtbo.img
#   -> AnyKernel3 zip (TWRP-flashable)
#
# Usage: ./scripts/build-reginkgo-style.sh
# Env:   CLANG_DIR=~/toolchains/aospclang   (toolchain, default: aospclang)
#        DO_KSU=1                           (merge ksu.config fragment)
#        LOCALVERSION="-GinkgoMainline-v1.0"
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/env.sh
source "$ROOT/scripts/env.sh"

JOBS="${JOBS:-$(nproc)}"
OUT="$ROOT/out"
AK3_DIR="${AK3_DIR:-$ROOT/out/AnyKernel3}"
ZIP_DIR="${ZIP_DIR:-$ROOT}"
DATE="$(date '+%Y%m%d-%H%M')"
LOCALVERSION="${LOCALVERSION:--GinkgoMainline-v1.0}"
CK_TYPE="Vanilla"
AK3_URL="https://github.com/Flopster101/AnyKernel3"
AK3_BRANCH="floppy-reborn"
FRAGMENTS=("$ROOT/config/ginkgo.fragment" "$ROOT/config/ginkgo-android.fragment")
DEFCONFIG="${DEFCONFIG:-defconfig}"
die() { echo "error: $*" >&2; exit 1; }

[[ -d "$KERNEL_SRC" ]] || die "kernel source missing at $KERNEL_SRC (run scripts/setup-kernel.sh)"

# --- Toolchain: AOSP Clang (like ReGinkgo) + llvm binutils -------------------
CLANG_DIR="${CLANG_DIR:-$HOME/toolchains/aospclang}"
[[ -x "$CLANG_DIR/bin/clang" ]] || die "clang not found at $CLANG_DIR/bin/clang"
export PATH="$CLANG_DIR/bin:$PATH"
export KBUILD_BUILD_USER="rafitadev"
export KBUILD_BUILD_HOST="ReGinkgo-Lab"
KBUILD_COMPILER_STRING="$("$CLANG_DIR/bin/clang" -v 2>&1 | head -n1 | sed 's/(https..*//')"
export KBUILD_COMPILER_STRING

echo "==> Toolchain: $KBUILD_COMPILER_STRING"

# --- Config: defconfig + fragments (android + fstab fw) -----------------------
mkdir -p "$KBUILD_OUTPUT"
cd "$KERNEL_SRC"

FW_FRAG="$(mktemp)"
echo "CONFIG_EXTRA_FIRMWARE_DIR=\"$ROOT/firmware/ginkgo\"" > "$FW_FRAG"
FRAGS=("$DEFCONFIG" "${FRAGMENTS[@]}" "$FW_FRAG")
if [[ "${DO_KSU:-}" == "1" && -f "$ROOT/reference/downstream/configs/ksu.config" ]]; then
	FRAGS+=("$ROOT/reference/downstream/configs/ksu.config")
	CK_TYPE="KSU"
fi
echo "==> Config: ${FRAGS[*]}"
"$KERNEL_SRC/scripts/kconfig/merge_config.sh" -m -O "$KBUILD_OUTPUT" "${FRAGS[@]}"
rm -f "$FW_FRAG"
make O="$KBUILD_OUTPUT" olddefconfig
scripts/config --file "$KBUILD_OUTPUT/.config" --set-str CONFIG_LOCALVERSION "$LOCALVERSION"
make O="$KBUILD_OUTPUT" olddefconfig

# --- Build ---------------------------------------------------------------------
echo "==> Building Image.gz + $DTB_NAME ($JOBS jobs)"
make O="$KBUILD_OUTPUT" -j"$JOBS" \
	LLVM=1 LLVM_IAS=1 \
	CC="clang" \
	CLANG_TRIPLE="aarch64-linux-gnu-" \
	CROSS_COMPILE="aarch64-linux-gnu-" \
	LD="ld.lld" \
	AR="llvm-ar" \
	NM="llvm-nm" \
	OBJCOPY="llvm-objcopy" \
	OBJDUMP="llvm-objdump" \
	STRIP="llvm-strip" \
	READELF="llvm-readelf" \
	HOSTCC="clang" \
	Image.gz dtbs

KREL="$(make O="$KBUILD_OUTPUT" -s kernelrelease)"
echo "==> Kernel release: $KREL"

mkdir -p "$OUT"
cp -f "$KBUILD_OUTPUT/arch/arm64/boot/Image.gz" "$OUT/Image.gz"
cp -f "$KBUILD_OUTPUT/arch/arm64/boot/dts/qcom/$DTB_NAME" "$OUT/$DTB_NAME"

# --- Apply Android fstab overlay to the DTB (same as build-bootimg-android.sh) --
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
DTB_FINAL="$TMP/$DTB_NAME-android.dtb"
echo "==> Applying android fstab overlay"
dtc -@ -I dtb -O dtb -o "$TMP/dtb-syms.dtb" "$OUT/$DTB_NAME" 2>/dev/null
dtc -@ -I dts -O dtb -o "$TMP/fstab.dtbo" "$ROOT/dts/ginkgo-android-fstab.dts" 2>/dev/null
fdtoverlay -i "$TMP/dtb-syms.dtb" -o "$DTB_FINAL" "$TMP/fstab.dtbo"

# --- Assemble Image.gz-dtb + dtb + empty dtbo (mainline: no DTBO overlays) ------
cat "$OUT/Image.gz" "$DTB_FINAL" > "$OUT/Image.gz-dtb"
cp -f "$DTB_FINAL" "$OUT/dtb"
"$ROOT/scripts/make-empty-dtbo.sh"

echo "==> Artifacts:"
ls -lh "$OUT/Image.gz-dtb" "$OUT/dtb" "$OUT/dtbo-empty.img"

# --- AnyKernel3 zip (ReGinkgo style) -------------------------------------------
ZIP_PATH="$ZIP_DIR/ReGinkgoMainline_$CK_TYPE-$DATE.zip"
rm -rf "$AK3_DIR"
git clone -q --depth=1 -b "$AK3_BRANCH" "$AK3_URL" "$AK3_DIR"
cp -f "$OUT/Image.gz-dtb" "$AK3_DIR/"
cp -f "$OUT/dtb" "$AK3_DIR/dtb"
cp -f "$OUT/dtbo-empty.img" "$AK3_DIR/dtbo.img"
cd "$AK3_DIR"
rm -f "$ZIP_DIR/ReGinkgoMainline_"*.zip
zip -r9 "$ZIP_PATH" * -x '*.git*' README.md '*placeholder' >/dev/null
cd "$ROOT"

echo "==> Done"
echo "Zip: $ZIP_PATH"
echo "Flash (TWRP): install the zip, then flash the A16 vendor/GSI as usual."
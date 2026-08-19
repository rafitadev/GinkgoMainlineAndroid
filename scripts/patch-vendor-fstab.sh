#!/usr/bin/env bash
# Strip hardware-wrapped-key / inline-crypto flags from the vendor fstab.
#
# The HyperOS 2 (Android 15) vendor fstab (/etc/fstab.qcom) marks /data and
# /metadata with `wrappedkey` and `inlinecrypt`. Those need Qualcomm ICE /
# hardware key management, which the mainline kernel does not implement —
# first-stage init would fail to mount /data. Editing the fstab to drop the
# flags makes Android fall back to software file-based encryption (fscrypt +
# dm-crypt, both built into the mainline kernel).
#
# Operates on a COPY (never the original). Works with raw or sparse ext4
# images via debugfs. Pass a loose vendor image to flash it back in fastboot.
#
# Usage: ./scripts/patch-vendor-fstab.sh <vendor.img> [out.img]
set -euo pipefail

SRC="${1:-}"
OUT="${2:-}"
[[ -n "$SRC" ]] || { echo "usage: $0 <vendor.img> [out.img]" >&2; exit 1; }
[[ -f "$SRC" ]] || { echo "no such file: $SRC" >&2; exit 1; }

command -v debugfs >/dev/null || { echo "debugfs not found (install e2fsprogs)" >&2; exit 1; }
command -v simg2img >/dev/null || { echo "simg2img not found (install android-simg2img)" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Normalize to a raw ext4 image if the source is sparse
RAW="$SRC"
if head -c 4 "$SRC" | grep -q $'\x3a\xff\x26\xed' || file "$SRC" | grep -qi sparse; then
	echo "==> Converting sparse -> raw"
	RAW="$TMP/vendor.raw"
	simg2img "$SRC" "$RAW"
fi

IMG="$TMP/vendor-patched.raw"
cp -f "$RAW" "$IMG"

echo "==> Listing fstab candidates in /etc"
debugfs -R "ls /etc" "$IMG" 2>/dev/null | grep -i fstab || true

FSTAB=""
for cand in fstab.qcom fstab.ginkgo fstab.emmc fstab; do
	if debugfs -R "stat /etc/$cand" "$IMG" >/dev/null 2>&1; then
		FSTAB="/etc/$cand"
		break
	fi
done
[[ -n "$FSTAB" ]] || { echo "no fstab found in vendor image" >&2; exit 1; }
echo "==> Patching $FSTAB"

debugfs -R "dump /etc/${FSTAB#/etc/} $TMP/fstab.orig" "$IMG" >/dev/null 2>&1

# Drop wrappedkey/inlinecrypt and fix the sdhci sysfs path (mainline is 4744000)
sed -E \
	-e 's/(,|^)wrappedkey(,|$)/\1/g' \
	-e 's/,inlinecrypt//g' \
	-e 's@4784000\.sdhci@4744000.sdhci@g' \
	"$TMP/fstab.orig" > "$TMP/fstab.new"

echo "==> fstab diff (old -> new):"
diff "$TMP/fstab.orig" "$TMP/fstab.new" || true

debugfs -w -R "rm /etc/${FSTAB#/etc/}" "$IMG" >/dev/null 2>&1
debugfs -w -R "write $TMP/fstab.new $FSTAB" "$IMG" >/dev/null 2>&1

# Done — if OUT is given, write the raw image there
if [[ -n "$OUT" ]]; then
	cp -f "$IMG" "$OUT"
	echo "==> Patched raw image written to $OUT"
else
	echo "==> Patched raw image: $IMG (flash me: fastboot flash vendor $IMG)"
fi
echo "Patched fstab:"
debugfs -R "cat $FSTAB" "$IMG" 2>/dev/null | grep -E "metadata|userdata"
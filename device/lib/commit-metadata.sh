#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/t75-common.sh"
PLAN=$1; BACK=$2
. "$PLAN"
mkdir -p "$BACK"

TMP="$BACK/metadata"
read_metadata_to "$TMP"
cur=$(metadata_committed "$TMP.1")
valid=$(metadata_valid "$TMP.1")
seq=$(metadata_seq "$TMP.1")
[ "$cur" = "$ACTIVE_SLOT" ] || die "metadata changed since prepare: committed=$cur expected=$ACTIVE_SLOT"

cp "$TMP.1" "$BACK/metadata.target.bin"

# These first fields are fixed in this metadata format. We validate their exact
# current strings before patching the single-byte slot values.
lines=$(metadata_lines "$BACK/metadata.target.bin")
echo "$lines" | grep -q "^COMMITTED=$ACTIVE_SLOT$" || die "unexpected COMMITTED encoding"
echo "$lines" | grep -q '^VALID=' || die "unexpected VALID encoding"
echo "$lines" | grep -q '^SEQ=' || die "unexpected SEQ encoding"

# COMMITTED digit is file offset 0x16; VALID digits are 0x1e and 0x20.
printf '%s' "$TARGET_SLOT" | dd of="$BACK/metadata.target.bin" bs=1 seek=22 conv=notrunc 2>/dev/null
printf '1' | dd of="$BACK/metadata.target.bin" bs=1 seek=30 conv=notrunc 2>/dev/null
printf '2' | dd of="$BACK/metadata.target.bin" bs=1 seek=32 conv=notrunc 2>/dev/null

# Keep SEQ byte-for-byte. For the dumps analyzed it is -1,-1 and Broadcom
# explicitly synthesizes order from COMMITTED. Retaining arbitrary existing SEQ
# avoids shifting the binary metadata tail.
dd if="$BACK/metadata.target.bin" bs=1 skip=12 count=252 2>/dev/null > "$BACK/meta.data"
be_crc32_file "$BACK/meta.data" > "$BACK/meta.crc"
dd if="$BACK/meta.crc" of="$BACK/metadata.target.bin" bs=1 seek=8 conv=notrunc 2>/dev/null

b=$(ubi_base)
ubiupdatevol "/dev/${b}_2" "$BACK/metadata.target.bin"
head -c 272 "/dev/${b}_2" > "$BACK/metadata2.after.bin"
cmp "$BACK/metadata.target.bin" "$BACK/metadata2.after.bin" >/dev/null || die "metadata2 readback mismatch"

ubiupdatevol "/dev/${b}_1" "$BACK/metadata.target.bin"
head -c 272 "/dev/${b}_1" > "$BACK/metadata1.after.bin"
cmp "$BACK/metadata.target.bin" "$BACK/metadata1.after.bin" >/dev/null || die "metadata1 readback mismatch"

echo "Metadata committed: $(metadata_lines "$BACK/metadata1.after.bin" | tr '\n' ' ')"

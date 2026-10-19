#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/t75-common.sh"

PLAN=$1
. "$PLAN"
UBI=$(find_ubi_for_image) || die "cannot locate image UBI"
B=$(basename "$UBI")
for x in ubimkvol ubirmvol ubiupdatevol sha256sum head wc; do need "$x"; done

confirm "Stage destination $DEST_FAMILY firmware into inactive slot $TARGET_SLOT?
Active slot: $ACTIVE_SLOT ($SOURCE_FAMILY)
Target IDs: bootfs=$BOOTFS_ID rootfs=$ROOTFS_ID zydefault=$ZYDEFAULT_ID zyfwinfo=$ZYFWINFO_ID zyfwsign=$ZYFWSIGN_ID
This will REMOVE/RECREATE only the target-slot firmware volumes."

create(){
    name=$1; id=$2; type=$3; vol_size=$4; payload_size=$5; file=$6; want=$7
    got=$(sha_file "$file"); [ "$got" = "$want" ] || die "source payload hash mismatch: $name"
    [ "$(wc -c < "$file")" -eq "$payload_size" ] || die "source payload size mismatch: $name"
    if vol_exists "$id"; then
        cur=$(vol_name "$id")
        echo "Removing inactive volume ID $id ($cur)"
        ubirmvol "$UBI" -n "$id"
    fi
    ubimkvol "$UBI" -n "$id" -N "$name" -t "$type" -s "$vol_size"
    ubiupdatevol "/dev/${B}_$id" "$file"
    got=$(read_exact_hash "/dev/${B}_$id" "$payload_size")
    [ "$got" = "$want" ] || die "$name readback hash mismatch"
    echo "PASS $name"
}

create "bootfs$TARGET_SLOT" "$BOOTFS_ID" static "$BOOTFS_SIZE" "$BOOTFS_SIZE" "$PAYLOAD_DIR/bootfs.bin" "$BOOTFS_SHA256"
create "rootfs$TARGET_SLOT" "$ROOTFS_ID" dynamic "$ROOTFS_SIZE" "$ROOTFS_SIZE" "$PAYLOAD_DIR/rootfs.bin" "$ROOTFS_SHA256"
# zydefault is a static UBIFS image, but its UBI volume is provisioned at
# 23 LEBs on both known stock families. The FIT payload itself is only 13 LEBs.
# Do not confuse payload length with UBI reserved capacity.
ZYDEFAULT_VOL_SIZE=5840896
create "zydefault$TARGET_SLOT" "$ZYDEFAULT_ID" static "$ZYDEFAULT_VOL_SIZE" "$ZYDEFAULT_SIZE" "$PAYLOAD_DIR/zydefault.bin" "$ZYDEFAULT_SHA256"
create "zyfwinfo$TARGET_SLOT" "$ZYFWINFO_ID" static "$ZYFWINFO_SIZE" "$ZYFWINFO_SIZE" "$PAYLOAD_DIR/zyfwinfo.bin" "$ZYFWINFO_SHA256"

if [ "$ZYFWSIGN_PRESENT" = 1 ]; then
    create "zyfwsign$TARGET_SLOT" "$ZYFWSIGN_ID" static "$ZYFWSIGN_SIZE" "$ZYFWSIGN_SIZE" "$PAYLOAD_DIR/zyfwsign.bin" "$ZYFWSIGN_SHA256"
else
    if vol_exists "$ZYFWSIGN_ID"; then
        echo "Removing stale inactive zyfwsign volume ID $ZYFWSIGN_ID for generic destination"
        ubirmvol "$UBI" -n "$ZYFWSIGN_ID"
    fi
fi
sync
echo "STAGE COMPLETE; metadata and loader remain unchanged."

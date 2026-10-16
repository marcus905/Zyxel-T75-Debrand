#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/t75-common.sh"
PLAN=$1; . "$PLAN"
check(){
    name=$1; id=$2; size=$3; want=$4
    vol_exists "$id" || die "missing $name ID $id"
    got=$(read_exact_hash "$(vol_dev "$id")" "$size")
    [ "$got" = "$want" ] || die "$name hash mismatch: $got != $want"
    echo "PASS $name ID=$id SHA256=$got"
}
check "bootfs$TARGET_SLOT" "$BOOTFS_ID" "$BOOTFS_SIZE" "$BOOTFS_SHA256"
check "rootfs$TARGET_SLOT" "$ROOTFS_ID" "$ROOTFS_SIZE" "$ROOTFS_SHA256"
check "zydefault$TARGET_SLOT" "$ZYDEFAULT_ID" "$ZYDEFAULT_SIZE" "$ZYDEFAULT_SHA256"
check "zyfwinfo$TARGET_SLOT" "$ZYFWINFO_ID" "$ZYFWINFO_SIZE" "$ZYFWINFO_SHA256"
if [ "$ZYFWSIGN_PRESENT" = 1 ]; then
    check "zyfwsign$TARGET_SLOT" "$ZYFWSIGN_ID" "$ZYFWSIGN_SIZE" "$ZYFWSIGN_SHA256"
else
    vol_exists "$ZYFWSIGN_ID" && die "generic destination unexpectedly has zyfwsign ID $ZYFWSIGN_ID"
fi
echo "STAGED SLOT VERIFY PASS"

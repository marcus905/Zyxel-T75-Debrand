#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/t75-common.sh"
PLAN=$1; . "$PLAN"
need dd

TMP=/tmp/t75-postcheck.$$
trap 'rm -f "$TMP"*' EXIT INT TERM
read_metadata_to "$TMP"
cur=$(metadata_committed "$TMP.1")
booted=$(cmdline_slot)
fam=$(detect_current_family "$cur")

[ "$cur" = "$TARGET_SLOT" ] || die "post-boot COMMITTED=$cur expected=$TARGET_SLOT"
[ "$booted" = "$TARGET_SLOT" ] || die "running rootfs$booted expected rootfs$TARGET_SLOT"
[ "$fam" = "$DEST_FAMILY" ] || die "running family=$fam expected=$DEST_FAMILY"

LOADER_MTD=$(find_mtd_num_by_name loader)
dd if="/dev/mtd$LOADER_MTD" of="$TMP.loader" bs=262144 count=8 2>/dev/null
once=$(loader_env_get "$TMP.loader" once)
[ "$once" = true ] || die "first-boot reset hook did not self-clear; once=$once"
echo "PASS first-boot reset hook self-cleared"

# Required shared first-boot state.
for pair in 10:data 11:defaults 12:zymisc; do
    id=${pair%%:*}; name=${pair#*:}
    vol_exists "$id" || die "destination did not recreate required shared volume $name (ID $id)"
    actual=$(vol_name "$id")
    [ "$actual" = "$name" ] || die "ID $id is named $actual, expected $name"
    echo "PASS recreated $name ID=$id size=$(vol_bytes "$id")"
done

# Proprietary optional volumes are reported, not required: stock logs show romfile
# creation can fail without preventing boot.
for pair in 13:romfile 14:rom-d 15:wwan; do
    id=${pair%%:*}; name=${pair#*:}
    if vol_exists "$id"; then
        echo "INFO optional $name recreated ID=$id size=$(vol_bytes "$id")"
    else
        echo "INFO optional $name is absent"
    fi
done

echo "POSTCHECK PASS: destination family initialized clean shared state"

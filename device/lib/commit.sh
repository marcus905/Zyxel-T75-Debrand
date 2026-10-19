#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/t75-common.sh"
PLAN=$1; . "$PLAN"
"$HERE/verify-stage.sh" "$PLAN"

confirm "FINAL COMMIT:
- metadata will select slot $TARGET_SLOT while keeping both slots valid
- the full 2MiB loader will be replaced with the $DEST_FAMILY loader stack
- device identity/current credentials will be translated and preserved
The script WILL NOT reboot automatically.\n- destination U-Boot will reset shared family state before Linux starts"

LOADER_MTD=$(find_mtd_num_by_name loader); [ -n "$LOADER_MTD" ] || die "loader MTD missing"
if [ -r "/sys/class/mtd/mtd${LOADER_MTD}/bad_blocks" ]; then
    bb=$(cat "/sys/class/mtd/mtd${LOADER_MTD}/bad_blocks")
    [ "$bb" = 0 ] || die "loader partition reports $bb bad block(s)"
fi
for x in dd nandwrite flash_erase sha256sum openssl sync; do need "$x"; done

RUN="$WORKDIR/commit-$(next_stamp)"
mkdir -p "$RUN"
dd if="/dev/mtd$LOADER_MTD" of="$RUN/loader.before.bin" bs=262144 count=8 2>/dev/null
sha256sum "$RUN/loader.before.bin" > "$RUN/loader.before.sha256"

out=$("$HERE/build-loader.sh" "$SOURCE_FAMILY" "$DEST_FAMILY" "$LOADER_TEMPLATE" "$RUN/loader.destination.bin" "$ENGDEBUG" "${RESET_SHARED:-1}")
echo "$out"
DEST_SHA=$(printf '%s\n' "$out" | sed -n 's/^DEST_LOADER_SHA256=//p' | tail -n1)
[ -n "$DEST_SHA" ] || die "could not obtain destination loader SHA"

"$HERE/commit-metadata.sh" "$PLAN" "$RUN"

flash_erase "/dev/mtd$LOADER_MTD" 0 0
nandwrite -p "/dev/mtd$LOADER_MTD" "$RUN/loader.destination.bin"

dd if="/dev/mtd$LOADER_MTD" of="$RUN/loader.after.bin" bs=262144 count=8 2>/dev/null
AFTER=$(sha_file "$RUN/loader.after.bin")
[ "$AFTER" = "$DEST_SHA" ] || die "loader readback mismatch"

printf '%s\n' "$DEST_SHA" > "$WORKDIR/destination-loader.sha256"
sync
echo "COMMIT COMPLETE. NO REBOOT PERFORMED."
echo "Next: t75.sh verify \"$WORKDIR\""

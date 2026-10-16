#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/t75-common.sh"

ROOT=$1
FULL=${2:-0}
mkdir -p "$ROOT"
for x in nanddump sha256sum head cp ubinfo; do need "$x"; done

TMP=/tmp/t75-meta.$$
trap 'rm -f "$TMP"*' EXIT INT TERM
read_metadata_to "$TMP"
COMMITTED=$(metadata_committed "$TMP.1")
BOOTED=$(cmdline_slot)
[ "$COMMITTED" = 1 ] || [ "$COMMITTED" = 2 ] || die "invalid COMMITTED=$COMMITTED"
[ -z "$BOOTED" ] || [ "$BOOTED" = "$COMMITTED" ] || die "metadata says slot $COMMITTED but kernel booted rootfs$BOOTED"
FAMILY=$(detect_current_family "$COMMITTED")

LOADER_MTD=$(find_mtd_num_by_name loader); [ -n "$LOADER_MTD" ] || die "loader MTD missing"
NAND_MTD=$(find_mtd_num_by_name brcmnand.0); [ -n "$NAND_MTD" ] || NAND_MTD=0

echo "Backing up loader..."
nanddump -n -l 2097152 -f "$ROOT/loader.bin" "/dev/mtd$LOADER_MTD" >/dev/null
sha256sum "$ROOT/loader.bin" > "$ROOT/loader.sha256"

cp /proc/mtd "$ROOT/proc-mtd.txt"
cp /proc/cmdline "$ROOT/proc-cmdline.txt"
ubinfo -a > "$ROOT/ubinfo.txt" 2>&1 || true
cp "$TMP.1" "$ROOT/metadata1.bin"; cp "$TMP.2" "$ROOT/metadata2.bin"

mkdir -p "$ROOT/environment"
for f in /proc/environment/*; do
    [ -r "$f" ] || continue
    n=$(basename "$f")
    cat "$f" > "$ROOT/environment/$n"
done

set -- $(slot_ids "$COMMITTED")
BOOTFS_ID=$1; ROOTFS_ID=$2; ZYDEFAULT_ID=$3; ZYFWINFO_ID=$4; ZYFWSIGN_ID=$5
: > "$ROOT/backup.conf"
{
 echo "BACKUP_FORMAT=1"
 echo "FAMILY=$FAMILY"
 echo "ACTIVE_SLOT=$COMMITTED"
 echo "BOOTFS_ID=$BOOTFS_ID"
 echo "ROOTFS_ID=$ROOTFS_ID"
 echo "ZYDEFAULT_ID=$ZYDEFAULT_ID"
 echo "ZYFWINFO_ID=$ZYFWINFO_ID"
 echo "ZYFWSIGN_ID=$ZYFWSIGN_ID"
} >> "$ROOT/backup.conf"

savevol(){
    key=$1; id=$2; file=$3
    vol_exists "$id" || die "active slot is missing $key volume ID $id"
    sz=$(vol_bytes "$id") || die "cannot read data_bytes for volume ID $id"
    head -c "$sz" "$(vol_dev "$id")" > "$ROOT/$file"
    got=$(sha_file "$ROOT/$file")
    upper=$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')
    {
      echo "${upper}_SIZE=$sz"
      echo "${upper}_SHA256=$got"
    } >> "$ROOT/backup.conf"
    echo "saved $key: $sz bytes $got"
}
savevol bootfs "$BOOTFS_ID" bootfs.bin
savevol rootfs "$ROOTFS_ID" rootfs.bin
savevol zydefault "$ZYDEFAULT_ID" zydefault.bin
savevol zyfwinfo "$ZYFWINFO_ID" zyfwinfo.bin
if vol_exists "$ZYFWSIGN_ID"; then
    savevol zyfwsign "$ZYFWSIGN_ID" zyfwsign.bin
    echo "ZYFWSIGN_PRESENT=1" >> "$ROOT/backup.conf"
else
    echo "ZYFWSIGN_PRESENT=0" >> "$ROOT/backup.conf"
fi


# Back up shared family state before a conversion reset. These logical UBI images
# are for disaster recovery; reverse conversion itself intentionally does not restore
# old-family shared state.
mkdir -p "$ROOT/shared"
sync
for pair in $(shared_ids); do
    id=${pair%%:*}; name=${pair#*:}
    if vol_exists "$id"; then
        sz=$(vol_bytes "$id") || die "cannot read shared volume size ID $id"
        type=dynamic
        ts=$(vol_sys "$id")
        [ ! -r "$ts/type" ] || type=$(cat "$ts/type")
        echo "Backing up shared $name (ID $id, $sz bytes, $type)..."
        head -c "$sz" "$(vol_dev "$id")" > "$ROOT/shared/$name.bin"
        h=$(sha_file "$ROOT/shared/$name.bin")
        {
          echo "SHARED_${id}_PRESENT=1"
          echo "SHARED_${id}_NAME='$name'"
          echo "SHARED_${id}_TYPE='$type'"
          echo "SHARED_${id}_SIZE='$sz'"
          echo "SHARED_${id}_SHA256='$h'"
        } >> "$ROOT/backup.conf"
    else
        echo "SHARED_${id}_PRESENT=0" >> "$ROOT/backup.conf"
    fi
done

if [ "$FULL" = 1 ]; then
    echo "Creating full logical NAND backup; this requires roughly 512 MiB free..."
    nanddump -n -f "$ROOT/full-mtd0.bin" "/dev/mtd$NAND_MTD" >/dev/null
    sha256sum "$ROOT/full-mtd0.bin" > "$ROOT/full-mtd0.sha256"
fi

cat > "$ROOT/sourcepack.conf" <<EOF
T75_SOURCEPACK_VERSION=1
FAMILY='$FAMILY'
ORIGIN='device-backup'
LOADER_PRESENT=1
LOADER_FILE='loader.bin'
BOOTFS_FILE='bootfs.bin'
ROOTFS_FILE='rootfs.bin'
ZYDEFAULT_FILE='zydefault.bin'
ZYFWINFO_FILE='zyfwinfo.bin'
ZYFWSIGN_PRESENT='$(grep "^ZYFWSIGN_PRESENT=" "$ROOT/backup.conf" | cut -d= -f2)'
EOF
for n in BOOTFS ROOTFS ZYDEFAULT ZYFWINFO ZYFWSIGN; do
    grep "^${n}_SIZE=" "$ROOT/backup.conf" >> "$ROOT/sourcepack.conf" || true
    grep "^${n}_SHA256=" "$ROOT/backup.conf" >> "$ROOT/sourcepack.conf" || true
done

echo "Backup complete: $ROOT"
echo "This directory can itself be used later as a conversion source."

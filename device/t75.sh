#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu
SELF=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LIB="$SELF/lib"
. "$LIB/t75-common.sh"

usage(){
cat <<EOF
Usage:
  $0 inspect
  $0 backup [--full]
  $0 prepare <vendor-firmware.bin|zip|source-pack|backup-directory> [--dest-family generic|odido] [--engdebug preserve|00|01] [--full-backup]
  $0 stage <work-directory>
  $0 verify-stage <work-directory>
  $0 commit <work-directory>
  $0 verify <work-directory>
  $0 reboot <work-directory>
  $0 postcheck <work-directory>

Set T75_YES=1 to accept confirmation prompts non-interactively.
prepare performs a standard reversible backup automatically. --full-backup also
creates a full logical mtd0 dump.
EOF
exit 2
}

inspect(){
    TMP=/tmp/t75-inspect.$$
    trap 'rm -f "$TMP"*' EXIT INT TERM
    read_metadata_to "$TMP"
    c=$(metadata_committed "$TMP.1"); v=$(metadata_valid "$TMP.1"); q=$(metadata_seq "$TMP.1")
    k=$(cmdline_slot)
    fam=$(detect_current_family "$c")
    set -- $(slot_ids "$c")
    echo "Metadata: COMMITTED=$c VALID=$v SEQ=$q"
    echo "Kernel rootfs slot: ${k:-unknown}"
    echo "Detected active family: $fam"
    echo "Active IDs: bootfs=$1 rootfs=$2 zydefault=$3 zyfwinfo=$4 zyfwsign=$5"
    if [ -n "$k" ] && [ "$k" != "$c" ]; then
        warn "metadata and running rootfs disagree; automatic conversion will refuse"
    fi
}

backup_cmd(){
    full=0
    [ "${1:-}" = --full ] && full=1
    d="$SELF/backups/backup-$(next_stamp)"
    confirm "Create $( [ "$full" = 1 ] && echo 'FULL mtd0 + ' || true )reversible backup at $d?"
    "$LIB/backup.sh" "$d" "$full"
}

prepare(){
    [ "$#" -ge 1 ] || usage
    src=$1; shift
    dest_override=
    engdebug=preserve
    full=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
          --dest-family) shift; [ "$#" -gt 0 ] || usage; dest_override=$1 ;;
          --engdebug) shift; [ "$#" -gt 0 ] || usage; engdebug=$1 ;;
          --full-backup) full=1 ;;
          *) die "unknown prepare option $1" ;;
        esac
        shift
    done
    [ -e "$src" ] || die "source not found: $src"
    case "$engdebug" in preserve|00|01) ;; *) die "--engdebug must be preserve, 00, or 01";; esac

    TMP=/tmp/t75-prepare.$$
    trap 'rm -f "$TMP"*' EXIT INT TERM
    read_metadata_to "$TMP"
    active=$(metadata_committed "$TMP.1")
    booted=$(cmdline_slot)
    [ "$active" = 1 ] || [ "$active" = 2 ] || die "bad COMMITTED=$active"
    [ -n "$booted" ] || die "cannot determine running rootfs slot from /proc/cmdline"
    [ "$booted" = "$active" ] || die "metadata says slot $active but running kernel is rootfs$booted"
    source_family=$(detect_current_family "$active")
    target=$((3-active))
    set -- $(slot_ids "$target")
    bid=$1; rid=$2; did=$3; fid=$4; sid=$5

    W="$SELF/work/convert-$(next_stamp)"
    mkdir -p "$W/payloads"
    PAYLOAD_DIR="$W/payloads"
    DEST_FAMILY=unknown
    LOADER_TEMPLATE=

    if [ -d "$src" ] && [ -f "$src/sourcepack.conf" ]; then
        SP="$src/sourcepack.conf"
        . "$SP"
        [ "${T75_SOURCEPACK_VERSION:-}" = 1 ] || die "unsupported source pack version"
        DEST_FAMILY=$FAMILY
        for n in bootfs rootfs zydefault zyfwinfo; do
            u=$(printf '%s' "$n" | tr '[:lower:]' '[:upper:]')
            eval "fn=\${${u}_FILE:-$n.bin}"
            [ -f "$src/$fn" ] || die "source pack lacks $fn"
            cp "$src/$fn" "$PAYLOAD_DIR/$n.bin"
            sz=$(wc -c < "$PAYLOAD_DIR/$n.bin"); h=$(sha_file "$PAYLOAD_DIR/$n.bin")
            eval "declsz=\${${u}_SIZE:-$sz}"; eval "declh=\${${u}_SHA256:-$h}"
            [ "$sz" = "$declsz" ] || die "$n source-pack size mismatch"
            [ "$h" = "$declh" ] || die "$n source-pack hash mismatch"
            eval "${u}_SIZE=\$sz"; eval "${u}_SHA256=\$h"
        done
        if [ "${ZYFWSIGN_PRESENT:-0}" = 1 ]; then
            fn=${ZYFWSIGN_FILE:-zyfwsign.bin}
            [ -f "$src/$fn" ] || die "source pack declares zyfwsign but lacks $fn"
            cp "$src/$fn" "$PAYLOAD_DIR/zyfwsign.bin"
            ZYFWSIGN_SIZE=$(wc -c < "$PAYLOAD_DIR/zyfwsign.bin")
            ZYFWSIGN_SHA256=$(sha_file "$PAYLOAD_DIR/zyfwsign.bin")
        else ZYFWSIGN_PRESENT=0; fi
        if [ "${LOADER_PRESENT:-0}" = 1 ]; then
            lf=${LOADER_FILE:-loader.bin}
            [ -f "$src/$lf" ] || die "source pack declares loader but lacks $lf"
            LOADER_TEMPLATE="$src/$lf"
        fi
    elif [ -d "$src" ] && [ -f "$src/backup.conf" ]; then
        . "$src/backup.conf"
        DEST_FAMILY=$FAMILY
        LOADER_TEMPLATE="$src/loader.bin"
        for n in bootfs rootfs zydefault zyfwinfo; do
            [ -f "$src/$n.bin" ] || die "backup lacks $n.bin"
            cp "$src/$n.bin" "$PAYLOAD_DIR/$n.bin"
        done
        for n in bootfs rootfs zydefault zyfwinfo; do
            u=$(printf '%s' "$n" | tr '[:lower:]' '[:upper:]')
            sz=$(wc -c < "$PAYLOAD_DIR/$n.bin"); h=$(sha_file "$PAYLOAD_DIR/$n.bin")
            eval "${u}_SIZE=\$sz"; eval "${u}_SHA256=\$h"
        done
        if [ "${ZYFWSIGN_PRESENT:-0}" = 1 ]; then
            cp "$src/zyfwsign.bin" "$PAYLOAD_DIR/zyfwsign.bin"
            ZYFWSIGN_SIZE=$(wc -c < "$PAYLOAD_DIR/zyfwsign.bin")
            ZYFWSIGN_SHA256=$(sha_file "$PAYLOAD_DIR/zyfwsign.bin")
        else ZYFWSIGN_PRESENT=0; fi
    else
        FW="$src"
        if echo "$src" | grep -qi '\.zip$'; then
            need unzip
            entry=$(unzip -Z1 "$src" | grep -Ei '\.bin$' | head -n1)
            [ -n "$entry" ] || die "zip contains no .bin firmware"
            echo "Extracting vendor update member: $entry"
            unzip -p "$src" "$entry" > "$W/vendor-update.bin"
            FW="$W/vendor-update.bin"
        fi
        "$LIB/fit-extract.sh" "$FW" "$PAYLOAD_DIR"
        . "$PAYLOAD_DIR/payloads.env"
        DEST_FAMILY=$DEST_FAMILY_DETECTED
        [ -f "$PAYLOAD_DIR/zyfwsign.bin" ] && ZYFWSIGN_PRESENT=1 || ZYFWSIGN_PRESENT=0
        if [ "$ZYFWSIGN_PRESENT" = 1 ]; then
            ZYFWSIGN_SIZE=$(wc -c < "$PAYLOAD_DIR/zyfwsign.bin")
            ZYFWSIGN_SHA256=$(sha_file "$PAYLOAD_DIR/zyfwsign.bin")
        fi
    fi

    [ -z "$dest_override" ] || DEST_FAMILY=$dest_override
    case "$DEST_FAMILY" in generic|odido) ;; *) die "cannot identify destination family; rerun with --dest-family generic|odido";; esac
    [ "$DEST_FAMILY" != "$source_family" ] || die "source and destination are both $source_family; this tool is for family conversion, use the vendor updater for same-family upgrades"
    if [ -z "$LOADER_TEMPLATE" ]; then
        LOADER_TEMPLATE="$SELF/../templates/loader-$DEST_FAMILY.bin.gz"
    fi
    [ -f "$LOADER_TEMPLATE" ] || die "destination loader template missing"

    # A standard logical backup is always made before we even stage.
    B="$SELF/backups/pre-convert-$(next_stamp)"
    confirm "Detected:
  current family: $source_family
  active/committed slot: $active
  destination family: $DEST_FAMILY
  inactive target slot: $target
  EngDebugFlag policy: $engdebug
  target IDs: bootfs=$bid rootfs=$rid zydefault=$did zyfwinfo=$fid zyfwsign=$sid
Shared first-boot policy:
  IDs 10..15 will be backed up now.
  Destination U-Boot will remove them before Linux starts.
  IDs 10/11/12 are expected to be recreated by destination init.
Create the pre-conversion backup and prepare this plan?"
    "$LIB/backup.sh" "$B" "$full"

    cat > "$W/plan.env" <<EOF
WORKDIR='$W'
BACKUP_DIR='$B'
SOURCE_FAMILY='$source_family'
DEST_FAMILY='$DEST_FAMILY'
ACTIVE_SLOT='$active'
TARGET_SLOT='$target'
ENGDEBUG='$engdebug'
RESET_SHARED='1'
PAYLOAD_DIR='$PAYLOAD_DIR'
LOADER_TEMPLATE='$LOADER_TEMPLATE'
BOOTFS_ID='$bid'
ROOTFS_ID='$rid'
ZYDEFAULT_ID='$did'
ZYFWINFO_ID='$fid'
ZYFWSIGN_ID='$sid'
BOOTFS_SIZE='$BOOTFS_SIZE'
BOOTFS_SHA256='$BOOTFS_SHA256'
ROOTFS_SIZE='$ROOTFS_SIZE'
ROOTFS_SHA256='$ROOTFS_SHA256'
ZYDEFAULT_SIZE='$ZYDEFAULT_SIZE'
ZYDEFAULT_SHA256='$ZYDEFAULT_SHA256'
ZYFWINFO_SIZE='$ZYFWINFO_SIZE'
ZYFWINFO_SHA256='$ZYFWINFO_SHA256'
ZYFWSIGN_PRESENT='$ZYFWSIGN_PRESENT'
EOF
    if [ "$ZYFWSIGN_PRESENT" = 1 ]; then
      {
        echo "ZYFWSIGN_SIZE='$ZYFWSIGN_SIZE'"
        echo "ZYFWSIGN_SHA256='$ZYFWSIGN_SHA256'"
      } >> "$W/plan.env"
    fi

    echo
    echo "PLAN READY: $W"
    echo "Backup: $B"
    echo "No firmware volumes, metadata, or loader have been modified."
    echo "Next: $0 stage '$W'"
}

need_plan(){
    [ "$#" -eq 1 ] || usage
    W=$1
    [ -f "$W/plan.env" ] || die "not a prepared work directory: $W"
    echo "$W/plan.env"
}

cmd=${1:-}; [ -n "$cmd" ] || usage; shift || true
case "$cmd" in
 inspect) inspect ;;
 backup) backup_cmd "${1:-}" ;;
 prepare) prepare "$@" ;;
 stage) p=$(need_plan "$@"); "$LIB/stage.sh" "$p" ;;
 verify-stage) p=$(need_plan "$@"); "$LIB/verify-stage.sh" "$p" ;;
 commit) p=$(need_plan "$@"); "$LIB/commit.sh" "$p" ;;
 verify) p=$(need_plan "$@"); "$LIB/verify-final.sh" "$p" ;;
 reboot)
    p=$(need_plan "$@")
    "$LIB/verify-final.sh" "$p"
    confirm "Final verification passed. Reboot into the newly committed slot? Destination U-Boot will clear cross-family shared state before Linux starts."
    sync; reboot
    ;;
 postcheck) p=$(need_plan "$@"); "$LIB/postcheck.sh" "$p" ;;
 *) usage ;;
esac

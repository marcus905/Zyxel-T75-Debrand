#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu

die(){ echo "ERROR: $*" >&2; exit 1; }
warn(){ echo "WARNING: $*" >&2; }
need(){ command -v "$1" >/dev/null 2>&1 || die "missing tool: $1"; }
sha_file(){ sha256sum "$1" | awk '{print $1}'; }

find_mtd_num_by_name(){
    awk -F: -v want="$1" '$2 ~ "\"" want "\"" {gsub("mtd","",$1); print $1}' /proc/mtd | head -n1
}
find_ubi_for_image(){
    IMAGE_MTD=$(find_mtd_num_by_name image)
    [ -n "$IMAGE_MTD" ] || die 'cannot find MTD named image'
    for s in /sys/class/ubi/ubi[0-9]*; do
        [ -f "$s/mtd_num" ] || continue
        if [ "$(cat "$s/mtd_num")" = "$IMAGE_MTD" ]; then
            echo "/dev/$(basename "$s")"
            return 0
        fi
    done
    return 1
}
ubi_base(){
    u=$(find_ubi_for_image) || die "cannot locate UBI attached to image"
    basename "$u"
}
vol_dev(){ b=$(ubi_base); echo "/dev/${b}_$1"; }
vol_sys(){ b=$(ubi_base); echo "/sys/class/ubi/${b}_$1"; }
vol_exists(){ [ -e "$(vol_dev "$1")" ]; }
vol_name(){ s=$(vol_sys "$1"); [ -r "$s/name" ] && cat "$s/name" || true; }
vol_bytes(){ s=$(vol_sys "$1"); [ -r "$s/data_bytes" ] || return 1; cat "$s/data_bytes"; }

read_exact_hash(){
    dev="$1"; size="$2"
    head -c "$size" "$dev" | sha256sum | awk '{print $1}'
}

be_crc32_file(){
    # gzip trailer is little-endian CRC32, exactly the same polynomial/result
    # used by the Broadcom metadata and BOOT_MAGIC code.
    gzip -c "$1" | tail -c 8 | head -c 4
}

confirm(){
    prompt=$1
    if [ "${T75_YES:-0}" = 1 ]; then return 0; fi
    [ -t 0 ] || die "$prompt (non-interactive; set T75_YES=1 to confirm)"
    printf "%s\nType YES to continue: " "$prompt"
    read ans
    [ "$ans" = YES ] || die "not confirmed"
}

slot_ids(){
    # Prints: bootfs rootfs zydefault zyfwinfo zyfwsign
    n=$1
    case "$n" in 1|2) ;; *) die "invalid slot $n";; esac
    echo "$((2*n+1)) $((2*n+2)) $((15+n)) $((17+n)) $((19+n))"
}

read_metadata_to(){
    out=$1
    b=$(ubi_base)
    d1="/dev/${b}_1"; d2="/dev/${b}_2"
    [ -e "$d1" ] && [ -e "$d2" ] || die "metadata volume IDs 1/2 missing"
    head -c 272 "$d1" > "$out.1"
    head -c 272 "$d2" > "$out.2"
    [ "$(wc -c < "$out.1")" -eq 272 ] || die "short metadata1 read"
    [ "$(wc -c < "$out.2")" -eq 272 ] || die "short metadata2 read"
    cmp "$out.1" "$out.2" >/dev/null || die "metadata1 and metadata2 differ"

    dd if="$out.1" bs=1 skip=12 count=252 2>/dev/null > "$out.data"
    be_crc32_file "$out.data" > "$out.calc"
    dd if="$out.1" bs=1 skip=8 count=4 2>/dev/null > "$out.stored"
    cmp "$out.calc" "$out.stored" >/dev/null || die "metadata CRC invalid"
}

metadata_lines(){
    f=$1
    dd if="$f" bs=1 skip=12 count=96 2>/dev/null | tr '\000' '\n' | head -n3
}
metadata_committed(){
    metadata_lines "$1" | sed -n 's/^COMMITTED=//p' | head -n1
}
metadata_valid(){
    metadata_lines "$1" | sed -n 's/^VALID=//p' | head -n1
}
metadata_seq(){
    metadata_lines "$1" | sed -n 's/^SEQ=//p' | head -n1
}
cmdline_slot(){
    sed -n 's/.*root=ubi:rootfs\([12]\).*/\1/p' /proc/cmdline | head -n1
}

detect_current_family(){
    slot=$1
    set -- $(slot_ids "$slot")
    sign_id=$5
    if vol_exists "$sign_id"; then
        echo odido
    else
        echo generic
    fi
}

next_stamp(){
    date +%Y%m%d-%H%M%S 2>/dev/null || echo manual-$$
}


shared_ids(){
    # Canonical shared Zyxel/Broadcom UBI volumes.
    # Prints: id:name
    echo "10:data 11:defaults 12:zymisc 13:romfile 14:rom-d 15:wwan"
}

loader_env_get(){
    # Read one variable from the first BOOT_MAGIC environment in a 2MiB loader file.
    f=$1; key=$2
    dd if="$f" bs=1 skip=$((0x8000c)) count=$((0x3ffc)) 2>/dev/null |
      tr '\000' '\n' | sed -n "s/^${key}=//p" | head -n1
}

shared_reset_once(){
    # U-Boot one-shot reset. It runs before sdk boot_img, while no UBIFS volume is mounted.
    #
    # It first removes all known shared family state. At the end, it only clears itself
    # if all six volumes are confirmed absent. Therefore a power loss before completion
    # leaves the command pending for the next boot.
    cat <<'EOF'
if ubi part image; then if ubi check data; then ubi remove data; fi; if ubi check defaults; then ubi remove defaults; fi; if ubi check zymisc; then ubi remove zymisc; fi; if ubi check romfile; then ubi remove romfile; fi; if ubi check rom-d; then ubi remove rom-d; fi; if ubi check wwan; then ubi remove wwan; fi; if ubi check data; then echo T75_RESET_INCOMPLETE; else if ubi check defaults; then echo T75_RESET_INCOMPLETE; else if ubi check zymisc; then echo T75_RESET_INCOMPLETE; else if ubi check romfile; then echo T75_RESET_INCOMPLETE; else if ubi check rom-d; then echo T75_RESET_INCOMPLETE; else if ubi check wwan; then echo T75_RESET_INCOMPLETE; else setenv once true; saveenv; echo T75_RESET_COMPLETE; fi; fi; fi; fi; fi; fi; fi
EOF
}

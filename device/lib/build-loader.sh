#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Build destination-format 2MiB loader using current device identity/credentials.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/t75-common.sh"

KEY=15f1524f197e2df8bf88154630146f4e92330696ce53b5067e2891c2cb977cee
IV=74f06bcf05c913f8db130c47f4261920
DATA_SIZE=16380
REC_SIZE=16396
TEMPLATE_DATA_OFF=$((0x8000c))

[ "$#" -ge 4 ] && [ "$#" -le 6 ] || die "usage: $0 <source-family> <dest-family> <template> <output> [EngDebugFlag:preserve|00|01] [reset-shared:0|1]"
SRC_FAMILY=$1; DST_FAMILY=$2; TEMPLATE=$3; OUT=$4; ENG_POLICY=${5:-preserve}; RESET_SHARED=${6:-0}
case "$RESET_SHARED" in 0|1) ;; *) die "reset-shared must be 0 or 1";; esac
case "$SRC_FAMILY:$DST_FAMILY" in generic:odido|odido:generic|generic:generic|odido:odido) ;; *) die "bad family pair";; esac
[ -f "$TEMPLATE" ] || die "missing loader template"
for x in dd tr awk grep wc gzip tail head cmp cp openssl sha256sum sed; do need "$x"; done
TPL_TMP=
case "$TEMPLATE" in
  *.gz)
    TPL_TMP=${TMPDIR:-/tmp}/t75-loader-template.$$
    gzip -dc "$TEMPLATE" > "$TPL_TMP" || die "failed to decompress loader template"
    TEMPLATE=$TPL_TMP
    ;;
esac
[ "$(wc -c < "$TEMPLATE")" -eq 2097152 ] || die "loader template is not exactly 2MiB"

getenvv(){
    f="/proc/environment/$1"
    [ -r "$f" ] || die "cannot read $f"
    tr -d '\r\n' < "$f"
}
case "$ENG_POLICY" in
  preserve)
    ENG=$(getenvv EngDebugFlag)
    case "$ENG" in 00|01) ;; *) die "current EngDebugFlag is '$ENG', expected 00 or 01";; esac
    ;;
  00|01) ENG=$ENG_POLICY ;;
  *) die "EngDebugFlag policy must be preserve, 00, or 01" ;;
esac
valid_ascii(){ [ -n "$1" ] && printf '%s' "$1" | LC_ALL=C grep -q '^[ -~][ -~]*$'; }
odido_dec(){
    v=$1
    p=$(printf '%s' "$v" | openssl base64 -d -A 2>/dev/null |
        openssl enc -d -aes-256-cbc -K "$KEY" -iv "$IV" -nopad -nosalt 2>/dev/null |
        sed 's/ *$//') || die "Odido credential decrypt failed"
    valid_ascii "$p" || die "decrypted Odido credential is not printable"
    printf '%s' "$p"
}
odido_enc(){
    p=$1; n=$(printf '%s' "$p" | wc -c)
    [ "$n" -ge 1 ] && [ "$n" -le 16 ] || die "Odido plaintext credential must be 1..16 bytes"
    printf '%-16s' "$p" |
        openssl enc -e -aes-256-cbc -K "$KEY" -iv "$IV" -nopad -nosalt 2>/dev/null |
        openssl base64 -A
}

SN=$(getenvv SerialNumber); SN81=$(getenvv SN81); MAC=$(getenvv ethaddr)
ADMIN_RAW=$(getenvv admin); SUPER_RAW=$(getenvv supervisor); PSK_RAW=$(getenvv WpaPskKey)

if [ "$SRC_FAMILY" = odido ]; then
    ADMIN=$(odido_dec "$ADMIN_RAW"); SUPER=$(odido_dec "$SUPER_RAW"); PSK=$(odido_dec "$PSK_RAW")
    [ "$(odido_enc "$ADMIN")" = "$ADMIN_RAW" ] || die "admin source round-trip failed"
    [ "$(odido_enc "$SUPER")" = "$SUPER_RAW" ] || die "supervisor source round-trip failed"
    [ "$(odido_enc "$PSK")" = "$PSK_RAW" ] || die "PSK source round-trip failed"
else
    ADMIN=$ADMIN_RAW; SUPER=$SUPER_RAW; PSK=$PSK_RAW
fi
if [ "$DST_FAMILY" = odido ]; then
    ADMIN_DST=$(odido_enc "$ADMIN"); SUPER_DST=$(odido_enc "$SUPER"); PSK_DST=$(odido_enc "$PSK")
    [ "$(odido_dec "$ADMIN_DST")" = "$ADMIN" ] || die "admin destination round-trip failed"
    [ "$(odido_dec "$SUPER_DST")" = "$SUPER" ] || die "supervisor destination round-trip failed"
    [ "$(odido_dec "$PSK_DST")" = "$PSK" ] || die "PSK destination round-trip failed"
else
    ADMIN_DST=$ADMIN; SUPER_DST=$SUPER; PSK_DST=$PSK
fi

TMP=${TMPDIR:-/tmp}/t75-loader.$$
mkdir -p "$TMP"; trap 'rm -rf "$TMP"; [ -z "${TPL_TMP:-}" ] || rm -f "$TPL_TMP"' EXIT INT TERM

dd if="$TEMPLATE" bs=1 skip=$TEMPLATE_DATA_OFF count=$DATA_SIZE 2>/dev/null |
 tr '\000' '\n' |
 awk 'BEGIN{done=0} {if(done)next; if($0==""){done=1;next} print}' > "$TMP/template.txt"

for k in SerialNumber SN81 ethaddr admin supervisor WpaPskKey EngDebugFlag once; do
    grep -q "^$k=" "$TMP/template.txt" || die "destination template lacks $k"
done

if [ "$RESET_SHARED" = 1 ]; then
    ONCE=$(shared_reset_once)
else
    ONCE=true
fi
# Reject embedded newlines because the environment serializer is line based.
case "$ONCE" in *'
'*) die "internal once command contains newline";; esac

awk -v sn="$SN" -v sn81="$SN81" -v mac="$MAC" -v ad="$ADMIN_DST" -v su="$SUPER_DST" -v psk="$PSK_DST" -v eng="$ENG" -v once="$ONCE" '
 /^SerialNumber=/{print "SerialNumber=" sn;next}
 /^SN81=/{print "SN81=" sn81;next}
 /^ethaddr=/{print "ethaddr=" mac;next}
 /^admin=/{print "admin=" ad;next}
 /^supervisor=/{print "supervisor=" su;next}
 /^WpaPskKey=/{print "WpaPskKey=" psk;next}
 /^EngDebugFlag=/{print "EngDebugFlag=" eng;next}
 /^once=/{print "once=" once;next}
 {print}' "$TMP/template.txt" > "$TMP/new.txt"

tr '\n' '\000' < "$TMP/new.txt" > "$TMP/data"
printf '\000\000' >> "$TMP/data"
sz=$(wc -c < "$TMP/data"); [ "$sz" -le "$DATA_SIZE" ] || die "rebuilt environment too large"
pad=$((DATA_SIZE-sz))
[ "$pad" -eq 0 ] || dd if=/dev/zero bs=1 count="$pad" 2>/dev/null | tr '\000' '\377' >> "$TMP/data"
[ "$(wc -c < "$TMP/data")" -eq "$DATA_SIZE" ] || die "environment size mismatch"

be_crc32_file "$TMP/data" > "$TMP/crc"
printf '\166\156\105\165\000\100\000\000' > "$TMP/record"
cat "$TMP/crc" "$TMP/data" >> "$TMP/record"
printf '\377\377\377\377' >> "$TMP/record"
[ "$(wc -c < "$TMP/record")" -eq "$REC_SIZE" ] || die "BOOT_MAGIC record size mismatch"

cp "$TEMPLATE" "$OUT"
for off in $((0x80000)) $((0x140000)) $((0x1a0000)); do
    dd if="$TMP/record" of="$OUT" bs=1 seek="$off" conv=notrunc 2>/dev/null
done
[ "$(wc -c < "$OUT")" -eq 2097152 ] || die "output loader size changed"

for off in $((0x80000)) $((0x140000)) $((0x1a0000)); do
    dd if="$OUT" bs=1 skip="$off" count="$REC_SIZE" 2>/dev/null > "$TMP/r.$off"
done
cmp "$TMP/r.524288" "$TMP/r.1310720" >/dev/null || die "loader environment copies 1/2 differ"
cmp "$TMP/r.524288" "$TMP/r.1703936" >/dev/null || die "loader environment copies 1/3 differ"

echo "DEST_LOADER_SHA256=$(sha_file "$OUT")"
echo "Loader personalized: identity preserved, credentials $SRC_FAMILY -> $DST_FAMILY, EngDebugFlag=$ENG (policy=$ENG_POLICY), reset_shared=$RESET_SHARED"

#!/bin/sh
# Pure sh/awk extractor for Zyxel/Broadcom outer FIT update packages.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/t75-common.sh"

[ "$#" -eq 2 ] || { echo "usage: $0 <firmware.bin> <output-dir>" >&2; exit 2; }
FW=$1
OUT=$2
[ -f "$FW" ] || die "missing firmware $FW"
mkdir -p "$OUT"
for x in dd od awk tail head sha256sum; do need "$x"; done

# Outer FIT DTBs on this family are small. Parse the first 64KiB as FDT using
# decimal bytes only, so this also works with BusyBox awk implementations that
# do not accept hexadecimal numeric literals.
dd if="$FW" bs=1 count=65536 2>/dev/null | od -An -v -tu1 | awk '
function u32(o){ return B[o]*16777216+B[o+1]*65536+B[o+2]*256+B[o+3] }
function strz(o,  s){s=""; while(B[o]!=0){s=s sprintf("%c",B[o]); o++} return s}
function hexval(o,n,  i,s){s=""; for(i=0;i<n;i++) s=s sprintf("%02x",B[o+i]); return s}
BEGIN{n=0}
{for(i=1;i<=NF;i++) B[n++]=$i}
END{
 if(n<40 || u32(0)!=3490578157){print "ERROR:not a FIT/DTB" > "/dev/stderr"; exit 2}
 total=u32(4); so=u32(8); st=u32(12)
 if(total>n){print "ERROR:FIT DTB exceeds 64KiB parser window" > "/dev/stderr"; exit 3}
 p=so; depth=0
 while(1){
  tok=u32(p); p+=4
  if(tok==1){
   name=strz(p); while(B[p]!=0)p++; p++; while(p%4)p++
   depth++; N[depth]=name
  } else if(tok==2){depth--}
  else if(tok==3){
   len=u32(p); no=u32(p+4); p+=8; prop=strz(st+no)
   path=""; for(k=1;k<=depth;k++){if(N[k]!="")path=path "/" N[k]}
   if(path ~ /^\/images\//){
    if(prop=="description") D[path]=strz(p)
    else if(prop=="data-position") P[path]=u32(p)
    else if(prop=="data-size") S[path]=u32(p)
    else if(prop=="value" && len==32 && path ~ /\/hash-/){
      par=path; sub(/\/hash-[^\/]*$/, "", par); H[par]=hexval(p,32)
    }
   }
   p+=len; while(p%4)p++
  } else if(tok==4){}
  else if(tok==9) break
  else {print "ERROR:bad DTB token " tok > "/dev/stderr"; exit 4}
 }
 for(x in D){
   if(D[x]=="bootfs"||D[x]=="rootfs"||D[x]=="zydefault"||D[x]=="zyfwinfo"||D[x]=="zyfwsign")
     print D[x] "|" P[x] "|" S[x] "|" H[x]
 }
}' > "$OUT/fit.tsv"

for req in bootfs rootfs zydefault zyfwinfo; do
    grep -q "^$req|" "$OUT/fit.tsv" || die "firmware FIT has no $req payload"
done

extract_range(){
    src=$1; pos=$2; size=$3; dst=$4
    blk=4096
    sb=$((pos/blk)); lead=$((pos%blk)); need=$((lead+size)); nb=$(((need+blk-1)/blk))
    dd if="$src" bs=$blk skip=$sb count=$nb 2>/dev/null |
        tail -c +$((lead+1)) | head -c "$size" > "$dst"
    [ "$(wc -c < "$dst")" -eq "$size" ] || die "short extraction: $dst"
}

: > "$OUT/payloads.env"
while IFS='|' read -r name pos size hash; do
    [ -n "$name" ] || continue
    extract_range "$FW" "$pos" "$size" "$OUT/$name.bin"
    got=$(sha_file "$OUT/$name.bin")
    [ -z "$hash" ] || [ "$got" = "$hash" ] || die "$name FIT SHA256 mismatch"
    upper=$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')
    eval "${upper}_SIZE=\$size"
    eval "${upper}_SHA=\$got"
    {
      echo "${upper}_SIZE=$size"
      echo "${upper}_SHA256=$got"
    } >> "$OUT/payloads.env"
done < "$OUT/fit.tsv"

# Family auto-detection. zyfwsign is decisive; otherwise use the known Zyxel
# branch IDs in zyfwinfo. Unknown branches require an explicit family later.
FAMILY=unknown
if [ -f "$OUT/zyfwsign.bin" ]; then
    FAMILY=odido
elif grep -aq 'ACHN' "$OUT/zyfwinfo.bin"; then
    FAMILY=generic
elif grep -aq 'ACDA' "$OUT/zyfwinfo.bin"; then
    FAMILY=odido
fi
echo "DEST_FAMILY_DETECTED=$FAMILY" >> "$OUT/payloads.env"

echo "Extracted and verified FIT payloads:"
cat "$OUT/fit.tsv"
echo "Detected destination family: $FAMILY"

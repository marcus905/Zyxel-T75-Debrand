#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/t75-common.sh"
PLAN=$1; . "$PLAN"
"$HERE/verify-stage.sh" "$PLAN"

TMP=/tmp/t75-final-meta.$$
trap 'rm -f "$TMP"* /tmp/t75-loader-final.$$' EXIT INT TERM
read_metadata_to "$TMP"
[ "$(metadata_committed "$TMP.1")" = "$TARGET_SLOT" ] || die "metadata does not commit target slot"
[ "$(metadata_valid "$TMP.1")" = "1,2" ] || die "metadata VALID is not 1,2"
echo "PASS metadata: $(metadata_lines "$TMP.1" | tr '\n' ' ')"

[ -f "$WORKDIR/destination-loader.sha256" ] || die "destination-loader.sha256 missing; commit not completed?"
want=$(cat "$WORKDIR/destination-loader.sha256")
LOADER_MTD=$(find_mtd_num_by_name loader)
nanddump -n -l 2097152 -f /tmp/t75-loader-final.$$ "/dev/mtd$LOADER_MTD" >/dev/null
got=$(sha_file /tmp/t75-loader-final.$$)
[ "$got" = "$want" ] || die "loader final SHA mismatch"
echo "PASS loader SHA256=$got"
if [ "${RESET_SHARED:-1}" = 1 ]; then
    once=$(loader_env_get /tmp/t75-loader-final.$$ once)
    [ "$once" != true ] || die "destination loader does not contain pending shared-state reset"
    echo "$once" | grep -q 'ubi remove data' || die "loader once hook lacks data reset"
    echo "$once" | grep -q 'ubi remove defaults' || die "loader once hook lacks defaults reset"
    echo "$once" | grep -q 'ubi remove zymisc' || die "loader once hook lacks zymisc reset"
    echo "PASS destination loader carries pending first-boot shared-state reset"
fi
echo "FINAL VERIFY PASS"

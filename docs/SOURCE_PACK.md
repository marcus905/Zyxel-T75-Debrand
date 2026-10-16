# T75 Source Pack v1

The source-pack format makes the on-device converter independent of where firmware material came from.

## Inputs

`tools/t75_sourcepack.py` accepts:

- a public vendor `.bin`;
- a vendor `.zip` containing a firmware `.bin`;
- a previous converter backup directory;
- a raw UBI `mtd2` image;
- a full raw `mtd0` image.

## Logical output

```text
sourcepack.conf
manifest.json
bootfs.bin
rootfs.bin
zydefault.bin
zyfwinfo.bin
zyfwsign.bin   # Odido only
loader.bin     # only when source supplied a loader
```

A public Zyxel update normally does not contain SPL/TPL, so it produces a source pack without `loader.bin`. The device converter then uses the bundled anonymized family loader template.

When a raw NAND image or exact converter backup contains a loader, the source-pack tool anonymizes its reusable `loader.bin`; the original exact backup is not modified.

## Family detection

The tool primarily distinguishes families from `zyfwsign` presence and `zyfwinfo` branch information (`ACHN` vs `ACDA`). Unknown inputs should be supplied with an explicit family override rather than guessed.

## Why logical UBI extraction matters

Raw NAND dumps contain EC/VID headers, erase counters, wear-leveling history and obsolete physical PEBs. The source pack reconstructs logical UBI volume payloads and does not copy raw UBI placement into another device.

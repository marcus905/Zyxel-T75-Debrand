<!-- SPDX-License-Identifier: GPL-2.0-or-later -->

# T75 Source Pack v1

The source-pack format makes the on-device converter independent of where firmware material came from.

## Inputs

`tools/t75_sourcepack.py` accepts:

- a public vendor `.bin`;
- a vendor `.zip` containing a firmware `.bin`;
- a previous converter backup directory;
- an ECC-corrected logical UBI `mtd2` image;
- an ECC-corrected logical full `mtd0` image.

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

When a logical MTD image or exact converter backup contains a loader, the source-pack tool anonymizes its reusable `loader.bin`; the original exact backup is not modified.

## Family detection

The tool primarily distinguishes families from `zyfwsign` presence and `zyfwinfo` branch information (`ACHN` vs `ACDA`). Unknown inputs should be supplied with an explicit family override rather than guessed.

## Why ECC-corrected logical UBI extraction matters

Logical MTD dumps still contain UBI EC/VID headers, erase counters, wear-leveling history and obsolete physical PEBs. The source pack reconstructs logical UBI volume payloads and does not copy physical UBI placement into another device.

Do **not** use a data-only dump captured with `nanddump -n`: that option bypasses NAND ECC, so corrected bit errors are lost and cannot be reconstructed later without the corresponding OOB/ECC information. Converter-generated full backups use ECC-corrected reads.


## Related documentation

- [HOWTO.md](HOWTO.md) — use a prepared Source Pack in the field-tested conversion.
- [LOADER_NVRAM.md](LOADER_NVRAM.md) — loader/template personalization details.
- [RECOVERY.md](RECOVERY.md) — converter backups that can be normalized into Source Packs.

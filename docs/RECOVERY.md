<!-- SPDX-License-Identifier: GPL-2.0-or-later -->

# Backup and recovery model

## Conversion backup

Every conversion should preserve at least:

- current 2 MiB loader;
- both metadata records;
- active `bootfs`, `rootfs`, `zydefault`, `zyfwinfo` and `zyfwsign` when present;
- logical shared volumes when present;
- `/proc/environment`;
- `/proc/mtd`;
- `/proc/cmdline`;
- `ubinfo` output;
- hashes and conversion plan.

These materials are also suitable for producing a reverse-family source pack later.

## Full backup

`--full-backup` additionally saves a complete **ECC-corrected logical** `mtd0` image. It contains the 512 MiB MTD data area but not NAND OOB bytes. This is the preferred converter-level disaster-recovery artifact and should be stored off-device.

Do not substitute a `nanddump -n` data-only image for this purpose: `-n` bypasses ECC and can preserve correctable bit errors as corrupted data.

## Shared state

Cross-family conversion intentionally does not restore old `data/defaults/zymisc` into the destination family. They are kept only for recovery/reference. Destination U-Boot removes IDs 10–15 before first Linux boot so destination init starts from a clean family-native state.

## Fallback

Both firmware slots remain valid at the metadata level during commit. This preserves the old firmware material on NAND. Cross-family fallback is not assumed to work symmetrically because Odido and generic loaders enforce different trust/volume semantics; loader restoration remains the reliable recovery path if the destination family cannot boot.


## Related documentation

- [HOWTO.md](HOWTO.md) — field-tested conversion and U-Boot zydefault repair procedure.
- [SOURCE_PACK.md](SOURCE_PACK.md) — using supported backups as reusable firmware sources.
- [FLASH_LAYOUT.md](FLASH_LAYOUT.md) — partition, UBI volume, and metadata layout used during recovery.

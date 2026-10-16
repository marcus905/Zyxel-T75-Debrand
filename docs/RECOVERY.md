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

`--full-backup` additionally saves the complete raw NAND (`mtd0`). This is the preferred disaster-recovery artifact and should be stored off-device.

## Shared state

Cross-family conversion intentionally does not restore old `data/defaults/zymisc` into the destination family. They are kept only for recovery/reference. Destination U-Boot removes IDs 10–15 before first Linux boot so destination init starts from a clean family-native state.

## Fallback

Both firmware slots remain valid at the metadata level during commit. This preserves the old firmware material on NAND. Cross-family fallback is not assumed to work symmetrically because Odido and generic loaders enforce different trust/volume semantics; loader restoration remains the reliable recovery path if the destination family cannot boot.

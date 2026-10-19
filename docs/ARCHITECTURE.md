# Architecture

## Scope

This project implements **family conversion only**:

- Odido / `ACDA` → generic Zyxel / `ACHN`
- generic Zyxel / `ACHN` → Odido / `ACDA`

Same-family upgrades are intentionally out of scope.

## Three layers

### 1. Source normalization

`tools/t75_sourcepack.py` converts supported inputs into a common logical source-pack format. Supported inputs include public vendor firmware, previous converter backups, ECC-corrected logical `mtd2` images, and ECC-corrected logical full `mtd0` images.

A source pack carries logical firmware payloads and, when available, an anonymized loader template. It never carries another device's live identity intentionally.

### 2. Device inspection, backup and staging

`device/t75.sh prepare` reads both metadata copies, validates their CRCs, requires them to agree, cross-checks `COMMITTED` against the running `rootfsN`, and chooses the other slot.

The active slot is backed up along with the current 2 MiB loader, shared volumes, environment, partition map and UBI information. An optional full ECC-corrected logical NAND backup can also be created.

The destination firmware is staged entirely into the inactive slot and read back before any loader change.

### 3. Commit and first-boot regeneration

The destination loader is built from a family template plus the current physical device's identity and credentials. Metadata is switched to the staged slot while keeping both slots valid. The full 2 MiB loader is then written and read back.

A cross-family conversion must not boot the destination firmware with source-family persistent configuration. Instead, the destination loader's existing U-Boot `once` hook removes shared UBI volumes before Linux mounts them. Destination first-boot logic recreates native state.

## Boot chain

```text
BCM4912 Boot ROM
  → SPL (mtd1)
  → TPL (mtd1)
  → selected bootfs FIT
      → ATF
      → U-Boot proper
      → zloader
      → DTBs/kernel
  → selected rootfs
  → Linux
```

`zloader` is embedded inside `bootfs`; it is not a separate UBI volume.

## Trust-chain difference

Odido and generic firmware are not just different root filesystems. Odido carries an additional RSA/signature path and `zyfwsignN` volume; the generic branch does not. The loader/environment semantics also differ, so the project treats conversion as a coherent family-stack transition rather than a mixed-image upgrade.

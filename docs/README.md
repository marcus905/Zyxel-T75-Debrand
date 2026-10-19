<!-- SPDX-License-Identifier: GPL-2.0-or-later -->

# Documentation

Start here if you are new to the project.

## Recommended reading order

1. [ODIDO_ACCESS.md](ODIDO_ACCESS.md) — obtain the Linux root SSH shell required on stock Odido firmware.
2. [SOURCE_PACK.md](SOURCE_PACK.md) — build the destination Source Pack from a vendor firmware package or supported backup.
3. [HOWTO.md](HOWTO.md) — field-tested Odido T75 -> generic Zyxel ACHN 2.1 conversion procedure.
4. [USAGE.md](USAGE.md) — concise command reference for the converter.
5. [RECOVERY.md](RECOVERY.md) — backup model, fallback assumptions, and recovery artifacts.

## Technical reference

- [ARCHITECTURE.md](ARCHITECTURE.md) — converter design, family-stack transition, and boot chain.
- [FLASH_LAYOUT.md](FLASH_LAYOUT.md) — MTD/UBI layout, slot IDs, shared volumes, and metadata.
- [LOADER_NVRAM.md](LOADER_NVRAM.md) — 2 MiB loader layout, BOOT_MAGIC environments, credentials, and anonymized templates.
- [TEST_PLAN.md](TEST_PLAN.md) — hardware-validation and regression checklist.
- [LICENSING.md](LICENSING.md) — GPL-2.0-or-later project licensing and loader-template provenance.

## What is hardware-validated

The tested path is **Odido T75 -> generic Zyxel V5.18(ACHN.2.1)C0**. It has survived the first conversion boot, a subsequent normal reboot, and a factory reset followed by another successful boot.

Reverse generic -> Odido conversion remains experimental until separately hardware-validated.

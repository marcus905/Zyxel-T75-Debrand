<!-- SPDX-License-Identifier: GPL-2.0-or-later -->

# Licensing and provenance

## Converter code and documentation

The original scripts, tools, and project documentation in this repository are licensed under the **GNU General Public License, version 2, or (at your option) any later version** (`GPL-2.0-or-later`). The canonical GPL v2 license text is provided in the top-level [`LICENSE`](../LICENSE) file. Source files carry the corresponding SPDX identifier.

## Loader templates

The repository includes two anonymized 2 MiB loader templates:

- `templates/loader-generic.bin.gz`
- `templates/loader-odido.bin.gz`

They contain U-Boot-derived bootloader code together with Zyxel/Broadcom platform-specific boot components and BOOT_MAGIC environment data.

Zyxel provides an official GPL/OSS source-request mechanism for code in its products that is covered by GPL, LGPL, or other OSI licenses:

https://www.zyxel.com/service-provider/global/en/gpl-oss-software-notice

Zyxel's public EX7501-B0 V5.18(ACHN.2.1)C0 release note also contains a Public Domain Software Announcements section identifying open-source software used by the product:

https://spdl.zyxel.com/EX7501-B0/firmware(public_version)/EX7501-B0_5.18(ACHN.2.1)C0.pdf

The complete 2 MiB loader is a composite binary. Although it includes U-Boot/open-source-derived portions, this repository does **not** assert that every byte of the full loader image is GPL-licensed. The project's `GPL-2.0-or-later` grant applies to the original converter code/documentation, **not** to these third-party loader binaries. Anyone redistributing the complete templates should review the applicable licenses and source-offer obligations for the included components.

## Template anonymization

The expected uncompressed hashes are recorded in `templates/TEMPLATE_INFO.json`. Run:

```sh
python3 tools/audit_loader_template.py templates/loader-generic.bin.gz templates/loader-odido.bin.gz
```

before publishing or replacing either template.

## Firmware images

Full Zyxel/Odido firmware images, raw NAND dumps, device backups, and user-specific conversion state are intentionally not included in this repository.

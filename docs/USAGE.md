# Usage

> Odido T75 -> generic Zyxel V5.18(ACHN.2.1)C0 has been validated on hardware. Reverse conversion and additional-device testing remain experimental. Keep UART attached and retain a verified full backup off-device.

## 1. Optional PC preprocessing

Convert a public firmware or raw backup into a Source Pack:

```sh
python3 tools/t75_sourcepack.py firmware.zip source-packs/ACHN
```

For a raw dump whose family cannot be inferred safely:

```sh
python3 tools/t75_sourcepack.py full-mtd0.bin source-packs/ODIDO --family odido
```

## 2. Verify bundled loader templates

Vendor update packages normally do not contain SPL/TPL. The repository includes the two anonymized family loader templates:

```text
templates/loader-generic.bin.gz
templates/loader-odido.bin.gz
```

Verify both templates with `python3 tools/audit_loader_template.py templates/loader-generic.bin.gz templates/loader-odido.bin.gz` before use. See [LICENSING.md](LICENSING.md) for provenance and licensing notes.

## 3. Copy repository + source pack to USB

Firmware/source packs and exact device backups remain separate from the repository checkout.

On the router, many USB sticks are mounted with `noexec`. Remount the stick executable before running the converter:

```sh
mount -o remount,exec /mnt/usb1_sdb1
```

Use the actual mount point shown by `mount` on your device. If the checkout was copied through Windows and shell scripts have CRLF line endings, normalize them before running:

```sh
find /mnt/usb1_sdb1/Zyxel-T75-Debrand -type f \( -name '*.sh' -o -name '*.py' \) -exec sed -i 's/\r$//' {} +
```

## 4. Inspect

```sh
cd /mnt/usb/Zyxel-T75-Debrand/device
./t75.sh inspect
```

## 5. Prepare and back up

Default: preserve the current `EngDebugFlag`.

```sh
./t75.sh prepare /mnt/usb/source-packs/ACHN --full-backup
```

Other policies:

```sh
./t75.sh prepare /mnt/usb/source-packs/ACHN --engdebug 00
./t75.sh prepare /mnt/usb/source-packs/ACHN --engdebug 01
```

`prepare` validates metadata/running slot, calculates the inactive slot, creates a conversion work directory, and backs up current state.

## 6. Stage and verify

```sh
./t75.sh stage <workdir>
./t75.sh verify-stage <workdir>
```

At this point the old active slot and loader are still in use.

## 7. Commit without rebooting

```sh
./t75.sh commit <workdir>
./t75.sh verify <workdir>
```

Commit personalizes and writes the destination loader and updates metadata. It does **not** reboot.

## 8. Reboot and postcheck

```sh
./t75.sh reboot <workdir>
```

Destination U-Boot executes the one-shot shared-state reset before Linux starts. After destination userspace is available again:

```sh
./t75.sh postcheck <workdir>
```

This checks the selected/running family and slot, confirms the U-Boot one-shot self-cleared, and verifies required shared volumes were recreated.


## Hardware-validated notes

The first live Odido -> generic conversion exposed two implementation details now reflected in the scripts:

- loader verification must use normal ECC-corrected MTD reads; raw `nanddump -n` can falsely report loader mismatches because it bypasses ECC;
- `zydefault` must match the stock UBI geometry: **static**, **23 reserved LEBs**, while only the actual UBIFS payload bytes are written. ACHN 2.1's payload is 3,301,376 bytes (13 LEBs), but its UBIFS superblock allows growth beyond 13 LEBs, so a 13-LEB UBI volume will not mount.

See [HOWTO.md](HOWTO.md) for the complete field-tested sequence.

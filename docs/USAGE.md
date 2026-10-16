# Usage

> The complete conversion path is not yet hardware-validated. Keep UART attached for the first test and retain a verified full backup off-device.

## 1. Optional PC preprocessing

Convert a public firmware or raw backup into a Source Pack:

```sh
python3 tools/t75_sourcepack.py firmware.zip source-packs/ACHN
```

For a raw dump whose family cannot be inferred safely:

```sh
python3 tools/t75_sourcepack.py full-mtd0.bin source-packs/ODIDO --family odido
```

## 2. Supply local loader templates

Vendor update packages normally do not contain SPL/TPL. Keep the two anonymized family loader templates outside Git and copy them locally as:

```text
templates/loader-generic.bin.gz
templates/loader-odido.bin.gz
```

Use `tools/audit_loader_template.py` before testing them.

## 3. Copy repository + source pack to USB

Firmware/source packs and exact device backups remain separate from the repository checkout.

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

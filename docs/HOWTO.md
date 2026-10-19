<!-- SPDX-License-Identifier: GPL-2.0-or-later -->

# Field-tested Odido T75 -> generic Zyxel HOWTO

This procedure documents the first successful hardware conversion of an Odido T75 / Zyxel EX7501-B0 to generic Zyxel **V5.18(ACHN.2.1)C0**.

It is intentionally conservative: stage and verify first, commit only after hashes match, keep UART attached, and do not discard the original full NAND/loader backups.

If you are starting from stock Odido firmware and do not already have a Linux root shell, complete [ODIDO_ACCESS.md](ODIDO_ACCESS.md) first. It documents the tested UART, supervisor-web, root-password recovery, and SSH-enablement procedure.

## What you need

- root shell on the running Odido firmware;
- UART connected and logging;
- a USB stick containing this repository;
- a prepared ACHN 2.1 Source Pack — see [SOURCE_PACK.md](SOURCE_PACK.md) for how to build one from the public Zyxel firmware package;
- the bundled anonymized generic loader template at `templates/loader-generic.bin.gz`;
- enough USB space for a full NAND backup.

Before starting, verify the bundled templates on a PC:

```sh
python3 tools/audit_loader_template.py templates/loader-generic.bin.gz templates/loader-odido.bin.gz
```

## 1. Mount the USB executable

Typical Zyxel mounts use `noexec`. Find the mount point with `mount`, then remount it with `exec`.

Example:

```sh
mount -o remount,exec /mnt/usb1_sdb1
```

If the files came through Windows, normalize line endings:

```sh
find /mnt/usb1_sdb1/Zyxel-T75-Debrand -type f \( -name '*.sh' -o -name '*.py' \) -exec sed -i 's/\r$//' {} +
```

## 2. Inspect the current device

```sh
USB=/mnt/usb1_sdb1
cd "$USB/Zyxel-T75-Debrand/device"
sh t75.sh inspect
```

Confirm:

- current family is Odido;
- running rootfs matches metadata `COMMITTED`;
- the inactive target slot is the one the converter plans to use.

Do not continue if metadata and the running slot disagree before conversion.

## 3. Prepare and back up

Example:

```sh
sh t75.sh prepare "$USB/Zyxel-T75-Debrand/source-packs/ACHN-2.1" --full-backup
```

Record the work directory printed by `prepare`:

```sh
W=/mnt/usb1_sdb1/Zyxel-T75-Debrand/device/work/convert-YYYYMMDD-HHMMSS
```

Verify that the full NAND backup and its SHA256 file exist. See [RECOVERY.md](RECOVERY.md) for what is captured and how those artifacts are intended to be used.

## 4. Stage the generic firmware into the inactive slot

```sh
sh t75.sh stage "$W"
sh t75.sh verify-stage "$W"
```

All destination payloads must pass exact read-back SHA256 verification.

For ACHN 2.1, the validated payloads are:

```text
bootfs     10348404 bytes
rootfs     73138176 bytes
zydefault   3301376 bytes
zyfwinfo         256 bytes
```

Important: `zydefault` is a **static** UBI volume with **23 reserved LEBs**, even though the current UBIFS image contains only 13 LEBs of data. See [FLASH_LAYOUT.md](FLASH_LAYOUT.md) for the slot/volume layout. The staging code must allocate the stock 23-LEB capacity and write only the 3,301,376-byte payload.

## 5. Commit

```sh
sh t75.sh commit "$W"
sh t75.sh verify "$W"
```

Do not reboot unless final verification passes.

The loader verifier must use a normal ECC-corrected MTD read. Do not use `nanddump -n` to decide whether the written loader matches: raw no-ECC reads can differ even when the logical MTD contents are correct.

## 6. Reboot with UART attached

```sh
sh t75.sh reboot "$W"
```

On the first generic boot, expect U-Boot/zloader to remove shared volumes 10-15, save the environment, and print:

```text
T75_RESET_COMPLETE
```

Then it should boot the target generic slot with a kernel command line containing:

```text
root=ubi:rootfs2
```

The generic Linux userspace should recreate its native shared volumes.

## 7. Verify zydefault initialization

A successful boot should show:

```text
>>>>> mtd zydefault2 was mounted! <<<<<
zcfg_schema.bin
use default config
```

If instead the mount reports `Invalid argument`, check the UBI geometry. For ACHN 2.1, `zydefault2` must be:

```text
vol_id          17
reserved_pebs   23
vol_type        static
name            zydefault2
```

The actual payload remains 3,301,376 bytes.

## 8. Postcheck

Once generic userspace is available:

```sh
cd "$USB/Zyxel-T75-Debrand/device"
sh t75.sh postcheck "$W"
cat /proc/cmdline
cat /proc/mtd
ubinfo -a
cat /proc/environment/EngDebugFlag
cat /proc/environment/once 2>/dev/null || true
```

Expected state:

- running rootfs is the generic target slot;
- metadata commits the same slot;
- `once=true`;
- shared volumes have been recreated;
- `zydefault` mounts successfully;
- Wi-Fi and the generic web UI are functional.

## Recovery note: repairing zydefault from U-Boot

If `zydefault2` was removed or created with the wrong geometry, it can be restored through TFTP from full U-Boot.

Known-good ACHN 2.1 payload:

```text
filename: zydefault.bin
size:     3301376 bytes (0x326000)
CRC32:    dfa66111
SHA256:   0bea5eac73699ed278661d370a33605f9a4f0d9da442b29a6e86820429fc8c33
```

Example U-Boot sequence:

```text
setenv ipaddr 192.168.222.1
setenv serverip 192.168.222.2
tftpboot 0x10000000 zydefault.bin
crc32 0x10000000 0x326000

ubi part image
ubi create zydefault2 0x592000 s 11
ubi write 0x10000000 zydefault2 0x326000
ubi read 0x11000000 zydefault2 0x326000
cmp.b 0x10000000 0x11000000 0x326000
```

In this U-Boot, the volume-ID argument is parsed as hexadecimal, so `11` means decimal ID 17.

Then boot normally:

```text
run bootcmd
```

## Validated result

The first hardware test reached generic Zyxel **V5.18(ACHN.2.1)C0**, mounted `zydefault2`, initialized the default data model, brought up both Wi-Fi radios, and presented the generic EX7501-B0 web interface. A normal second boot also succeeded. A factory reset performed from the generic firmware completed successfully and the device booted cleanly again afterward.

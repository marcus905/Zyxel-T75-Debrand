<!-- SPDX-License-Identifier: GPL-2.0-or-later -->

# Loader and NVRAM

## 2 MiB loader

The 2 MiB `mtd1` contains redundant SPL/TPL/platform regions plus three BOOT_MAGIC environment copies. Family conversion replaces the complete loader with the destination family's template after personalizing its environment for the current physical device.

## BOOT_MAGIC environment

Three copies are located at:

- `0x080000`
- `0x140000`
- `0x1a0000`

Each record begins:

```text
+0x0000  LE magic 0x75456e76
+0x0004  LE env_t size 0x4000
+0x0008  LE CRC32
+0x000c  0x3ffc bytes environment data
```

CRC32 is calculated over the `0x3ffc`-byte environment data area. The observed serialization is NUL-separated `key=value` entries followed by a three-NUL terminator and `0xff` padding.

## Per-device fields

The loader builder replaces these fields from the running router:

- `SerialNumber`
- `SN81`
- `ethaddr`
- `admin`
- `supervisor`
- `WpaPskKey`

It also applies the selected `EngDebugFlag` policy and installs the first-boot `once` command.

## Credential representation

Generic firmware stores the relevant credentials as plaintext-like environment values.

Odido uses a reversible fixed representation:

1. plaintext padded with ASCII spaces to 16 bytes;
2. AES-256-CBC with the reversed fixed family key/IV;
3. no PKCS#7 padding;
4. Base64 ciphertext.

The converter verifies decrypt/encrypt round-trips before accepting a generated loader.

## Anonymized templates

Files in `templates/` use placeholders rather than donor identity:

```text
SerialNumber=T75_TEMPLATE
SN81=T75_TEMPLATE
ethaddr=02:00:00:00:00:00
admin=T75_TEMPLATE
supervisor=T75_TEMPLATE
WpaPskKey=T75_TEMPLATE
EngDebugFlag=00
once=true
```

They are reusable family baselines and must not be flashed directly.


## Related documentation

- [templates/README.md](../templates/README.md) — bundled template handling and audit procedure.
- [LICENSING.md](LICENSING.md) — template provenance and licensing boundary.
- [ARCHITECTURE.md](ARCHITECTURE.md) — how loader replacement fits into family conversion.

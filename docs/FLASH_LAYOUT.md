# Flash and UBI layout

## Physical NAND

Observed device geometry:

- NAND: 512 MiB
- eraseblock: `0x40000` (256 KiB)
- `loader` / `mtd1`: 2 MiB
- `image` / `mtd2`: remaining UBI-backed image area

The physical MTD layout is the same across the analyzed Odido and stock devices. The family differences are primarily in UBI volume population and loader/NVRAM content.

## UBI volume IDs

| Purpose | Slot 1 | Slot 2 |
|---|---:|---:|
| metadata | 1 | 2 |
| bootfs | 3 | 5 |
| rootfs | 4 | 6 |
| zydefault | 16 | 17 |
| zyfwinfo | 18 | 19 |
| zyfwsign | 20 | 21 |

`zyfwsign` exists for Odido and is absent for generic firmware.\n\nOn both analyzed stock families, `zydefaultN` is a **static** UBI volume with **23 reserved LEBs** (LEB size 253,952 bytes). The filesystem payload may occupy fewer LEBs; ACHN 2.1 uses 13 LEBs / 3,301,376 bytes. Volume capacity and payload length must therefore be treated separately.

Shared volumes:

| ID | Name |
|---:|---|
| 10 | `data` |
| 11 | `defaults` |
| 12 | `zymisc` |
| 13 | `romfile` |
| 14 | `rom-d` |
| 15 | `wwan` |

The converter does not copy these shared volumes between families. They are backed up, removed by destination U-Boot on first boot, and recreated by destination userspace.

## Metadata

The logical metadata fields are:

```text
COMMITTED=N
VALID=x,y
SEQ=a,b
```

`VALID=1,2` means both slots are valid. The analyzed images use redundant metadata volumes protected by CRC32. The converter requires the two copies to agree before committing a conversion.

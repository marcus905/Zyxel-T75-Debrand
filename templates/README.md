# Loader templates

The two anonymized 2 MiB generic/Odido loader templates are committed in this directory:

```text
templates/loader-generic.bin.gz
templates/loader-odido.bin.gz
```

They are family baselines, not ready-to-flash images. The converter rebuilds their BOOT_MAGIC environments using the current device's identity, current credentials translated into the destination representation, the selected `EngDebugFlag` policy, and the first-boot `once` hook before writing `mtd1`.

A full NAND/device backup can also be normalized with `tools/t75_sourcepack.py`; any loader emitted into the reusable source pack is anonymized automatically, while the original exact backup stays untouched.

Audit the committed templates with:

```sh
python3 tools/audit_loader_template.py templates/loader-generic.bin.gz templates/loader-odido.bin.gz
```

`TEMPLATE_INFO.json` records the expected anonymized environment convention and known template hashes from the reference analysis.


## Licensing and provenance

The loader templates contain U-Boot-derived bootloader code together with platform-specific boot components and data. Zyxel provides a GPL/OSS source-request mechanism for software in its products that is covered by GPL, LGPL, or other OSI licenses. See [../docs/LICENSING.md](../docs/LICENSING.md).

Because each 2 MiB loader is a composite image, this project does not claim that every byte of the complete loader image is covered by the GPL.

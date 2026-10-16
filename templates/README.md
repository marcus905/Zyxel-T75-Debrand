# Loader templates

The actual 2 MiB generic/Odido loader templates are intentionally **not committed** to this repository. Keep local anonymized copies at:

```text
templates/loader-generic.bin.gz
templates/loader-odido.bin.gz
```

They are family baselines, not ready-to-flash images. The converter rebuilds their BOOT_MAGIC environments using the current device's identity, current credentials translated into the destination representation, the selected `EngDebugFlag` policy, and the first-boot `once` hook before writing `mtd1`.

A full NAND/device backup can also be normalized with `tools/t75_sourcepack.py`; any loader emitted into the reusable source pack is anonymized automatically, while the original exact backup stays untouched.

Audit local templates with:

```sh
python3 tools/audit_loader_template.py templates/loader-generic.bin.gz templates/loader-odido.bin.gz
```

`TEMPLATE_INFO.json` records the expected anonymized environment convention and known template hashes from the reference analysis.

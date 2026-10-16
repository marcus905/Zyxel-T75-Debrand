# Loader templates

These 2 MiB files are anonymized family baselines, not ready-to-flash images.

The converter must rebuild their BOOT_MAGIC environments using the current device's identity, current credentials translated into the destination representation, the selected `EngDebugFlag` policy, and the first-boot `once` hook before writing `mtd1`.

Run:

```sh
python3 tools/audit_loader_template.py templates/loader-generic.bin.gz templates/loader-odido.bin.gz
```

to audit the three environment copies and CRCs.

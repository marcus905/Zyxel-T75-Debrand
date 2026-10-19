# Hardware validation plan

The first Odido -> generic ACHN 2.1 conversion has completed successfully on hardware. Use this plan for regression testing, reverse conversion, and additional devices.

## Before commit

- Verify full raw backup hash off-device.
- Verify metadata1/metadata2 agree and CRCs pass.
- Verify running rootfs matches `COMMITTED`.
- Confirm calculated target slot is inactive.
- Stage and read-back hash every destination volume.
- Audit the generated destination loader, including all three BOOT_MAGIC copies.
- Keep UART connected and log output.

## Commit

- Run `commit` only after staged-slot verification passes.
- Do not reboot automatically outside `t75.sh reboot`.
- Run final verification and record loader SHA256.

## First destination boot

Watch U-Boot for the shared-state one-shot. The expected successful marker is:

```text
T75_RESET_COMPLETE
```

Then observe destination Linux recreate its shared volumes. Stock logs already demonstrate automatic creation/population behavior for `data/defaults`, and the EX7501 init path handles `zymisc`/proprietary shared volumes.

## Postcheck

Require:

- destination family detected;
- destination slot is both committed and running;
- `once=true` after first boot;
- IDs 10/11/12 recreated with expected names;
- normal management/network services available.

Capture the full UART log and use it to tighten the automated checks before a second device is converted.


## Regression checks learned from the first live run

- USB checkout can be mounted `noexec`; verify scripts are executable after `mount -o remount,exec <mountpoint>`.
- Verify loader writes through normal ECC-corrected MTD reads, not `nanddump -n`.
- Assert `zydefault` geometry, not only payload hash:
  - static UBI type;
  - 23 reserved LEBs;
  - payload bytes/hash match the source pack.
- Require a successful `zydefaultN` mount in the first destination boot log.
- Require the destination data model to initialize from `zcfg_schema.bin`.
- Confirm management UI and both Wi-Fi radios after first boot.


## Factory-reset regression

Validated on the first converted Odido -> generic ACHN 2.1 device:

- normal second boot after conversion succeeds;
- factory reset from the generic firmware succeeds;
- the subsequent boot succeeds;
- generic defaults/shared state regenerate cleanly;
- Wi-Fi and management UI return after reset.

Repeat this regression on additional devices and after reverse-conversion support is validated.

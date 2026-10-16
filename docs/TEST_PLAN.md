# First hardware test plan

The first live conversion should be treated as an experiment, not a routine procedure.

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

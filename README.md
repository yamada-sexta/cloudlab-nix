# cloudlab-nix

CloudLab repo-based profile that boots an Ubuntu base image, runs `nixos-infect`,
and reboots into NixOS.

## SSH behavior

The NixOS bootstrap preserves the CloudLab SSH access that already exists on the
base image for the configured `cloudlabUser`. That same username is created on
NixOS.

If `githubUser` is set, the profile also fetches that account's public GitHub
keys and adds them alongside the preserved CloudLab keys on both the initial
Ubuntu system and the resulting NixOS system.

## Console and boot behavior

The generated NixOS config explicitly keeps serial console output on `ttyS0`,
enables a serial getty there, and enables OpenSSH with the preserved key set.
That is intended to keep both the CloudLab web console and SSH usable after the
post-infect reboot.

## Compatibility note

CloudLab's profile execution environment appears to parse `profile.py` with an
older Python runtime. In practice, this means `profile.py` should stay compatible
with pre-Python-3.6 syntax.

Rules for future edits:

- Do not use f-strings in `profile.py`.
- Prefer conservative Python syntax in `profile.py` over newer conveniences.
- The node bootstrap logic itself lives in `setup-nixos.sh`, but the CloudLab
  profile definition in `profile.py` is the part that must remain old-Python-safe.

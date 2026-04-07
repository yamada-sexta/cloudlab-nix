# cloudlab-nix

CloudLab repo-based profile that boots an Ubuntu base image, runs `nixos-infect`,
and reboots into NixOS.

## Compatibility note

CloudLab's profile execution environment appears to parse `profile.py` with an
older Python runtime. In practice, this means `profile.py` should stay compatible
with pre-Python-3.6 syntax.

Rules for future edits:

- Do not use f-strings in `profile.py`.
- Prefer conservative Python syntax in `profile.py` over newer conveniences.
- The node bootstrap logic itself lives in `setup-nixos.sh`, but the CloudLab
  profile definition in `profile.py` is the part that must remain old-Python-safe.

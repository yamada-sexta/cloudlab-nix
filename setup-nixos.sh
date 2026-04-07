#!/bin/bash
set -euxo pipefail

GITHUB_USER="${1:?missing GitHub username}"
LOCAL_USER="${2:?missing local username}"

log() {
    printf '[setup-nixos] %s\n' "$*"
}

# Startup services can race early network bring-up, so give DHCP a few tries.
for _ in $(seq 1 30); do
    if curl -fsS https://github.com >/dev/null; then
        break
    fi
    sleep 2
done

KEYS_NIX="$(curl -fsS "https://github.com/${GITHUB_USER}.keys" | awk '{print "\"" $0 "\""}' || true)"
if [ -z "${KEYS_NIX}" ]; then
    log "No GitHub keys found for ${GITHUB_USER}; keeping CloudLab access only."
    KEYS_NIX="\"\""
fi

# Define the NixOS configuration
cat <<EOF > /root/custom-cloudlab.nix
{ config, pkgs, ... }:
{
  imports = [
    (builtins.fetchTarball "https://github.com/mars-research/miniond/archive/main.tar.gz" + "/nixos/recommended-no-flakes.nix")
  ];

  networking.useNetworkd = true;
  systemd.network.enable = true;
  systemd.network.networks."10-cloudlab-dhcp" = {
    matchConfig.Name = "en* eth*";
    networkConfig.DHCP = "ipv4";
  };

  boot.kernelParams = [ "console=ttyS0,115200n8" "console=tty0" ];
  services.openssh.enable = true;

  users.users.root.openssh.authorizedKeys.keys = [ $KEYS_NIX ];
  users.users.${LOCAL_USER} = {
    isNormalUser = true;
    extraGroups = [ "wheel" "systemd-network" ];
    openssh.authorizedKeys.keys = [ $KEYS_NIX ];
  };

  security.sudo.wheelNeedsPassword = false;
}
EOF

export NIXOS_IMPORT=/root/custom-cloudlab.nix
curl -fsSL https://raw.githubusercontent.com/elitak/nixos-infect/master/nixos-infect -o /root/nixos-infect
chmod +x /root/nixos-infect

log "Starting nixos-infect for ${LOCAL_USER}"
/root/nixos-infect 2>&1 | tee /var/log/nixos-infect.log

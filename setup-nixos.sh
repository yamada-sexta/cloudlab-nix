#!/bin/bash
GITHUB_USER=$1
KEYS_NIX=$(curl -s https://github.com/${GITHUB_USER}.keys | awk '{print "\"" $0 "\""}')

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
  users.users.yamada = {
    isNormalUser = true;
    extraGroups = [ "wheel" "systemd-network" ];
    openssh.authorizedKeys.keys = [ $KEYS_NIX ];
  };

  security.sudo.wheelNeedsPassword = false;
}
EOF

export NIXOS_IMPORT=/root/custom-cloudlab.nix
curl -L https://raw.githubusercontent.com/elitak/nixos-infect/master/nixos-infect -o nixos-infect
chmod +x nixos-infect
./nixos-infect 2>&1 | tee /var/log/nixos-infect.log
#!/bin/bash
set -euxo pipefail

CLOUDLAB_USER="${1:?missing CloudLab username}"
GITHUB_USER="${2:-}"

log() {
    printf '[setup-nixos] %s\n' "$*"
}

KEYS_FILE="$(mktemp)"
trap 'rm -f "${KEYS_FILE}"' EXIT

append_cloudlab_keys() {
    local user_home auth_keys

    user_home="$(getent passwd "${CLOUDLAB_USER}" | cut -d: -f6 || true)"
    if [ -z "${user_home}" ]; then
        log "Could not determine home directory for ${CLOUDLAB_USER}"
        return
    fi

    auth_keys="${user_home}/.ssh/authorized_keys"
    if [ -f "${auth_keys}" ]; then
        log "Preserving CloudLab authorized_keys from ${auth_keys}"
        cat "${auth_keys}" >> "${KEYS_FILE}"
        return
    fi

    log "No authorized_keys found for ${CLOUDLAB_USER} at ${auth_keys}"
}

append_github_keys() {
    if [ -z "${GITHUB_USER}" ]; then
        return
    fi

    # Startup services can race early network bring-up, so give DHCP a few tries.
    for _ in $(seq 1 30); do
        if curl -fsS https://github.com >/dev/null; then
            break
        fi
        sleep 2
    done

    if curl -fsS "https://github.com/${GITHUB_USER}.keys" >> "${KEYS_FILE}"; then
        log "Fetched GitHub keys for ${GITHUB_USER}"
    else
        log "No GitHub keys found for ${GITHUB_USER}; continuing with CloudLab keys only."
    fi
}

install_ubuntu_keys() {
    local user_home ssh_dir auth_keys

    user_home="$(getent passwd "${CLOUDLAB_USER}" | cut -d: -f6 || true)"
    if [ -z "${user_home}" ]; then
        log "Could not determine home directory for ${CLOUDLAB_USER}; skipping Ubuntu key install."
        return
    fi

    ssh_dir="${user_home}/.ssh"
    auth_keys="${ssh_dir}/authorized_keys"

    install -d -m 700 -o "${CLOUDLAB_USER}" -g "${CLOUDLAB_USER}" "${ssh_dir}"
    touch "${auth_keys}"
    cat "${KEYS_FILE}" | awk 'NF && !seen[$0]++' > "${auth_keys}.tmp"
    chown "${CLOUDLAB_USER}:${CLOUDLAB_USER}" "${auth_keys}.tmp"
    chmod 600 "${auth_keys}.tmp"
    mv "${auth_keys}.tmp" "${auth_keys}"
}

build_nix_keys() {
    awk '
        NF && !seen[$0]++ {
            gsub(/"/, "\\\"", $0)
            printf "\"%s\" ", $0
        }
    ' "${KEYS_FILE}"
}

append_cloudlab_keys
append_github_keys
install_ubuntu_keys
KEYS_NIX="$(build_nix_keys)"

mkdir -p /etc/nixos

# Define the NixOS configuration in /etc/nixos so nixos-infect preserves it
# during the lustration step and future rebuilds can still import it.
cat <<EOF > /etc/nixos/cloudlab-import.nix
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
  networking.firewall.enable = false;

  boot.kernelParams = [ "console=ttyS0,115200n8" "console=tty0" ];
  boot.loader.grub.extraConfig = ''
    serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1
    terminal_input serial console
    terminal_output serial console
  '';
  systemd.services."serial-getty@ttyS0".wantedBy = [ "getty.target" ];

  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;
  services.openssh.settings.KbdInteractiveAuthentication = false;
  services.openssh.settings.PermitRootLogin = "prohibit-password";

  users.users.root.openssh.authorizedKeys.keys = [ $KEYS_NIX ];
  users.users.${CLOUDLAB_USER} = {
    isNormalUser = true;
    extraGroups = [ "wheel" "systemd-network" ];
    openssh.authorizedKeys.keys = [ $KEYS_NIX ];
  };

  security.sudo.wheelNeedsPassword = false;
}
EOF

export NIXOS_IMPORT=/etc/nixos/cloudlab-import.nix
curl -fsSL https://raw.githubusercontent.com/elitak/nixos-infect/master/nixos-infect -o /root/nixos-infect
chmod +x /root/nixos-infect

log "Starting nixos-infect for ${CLOUDLAB_USER}"
/root/nixos-infect 2>&1 | tee /var/log/nixos-infect.log

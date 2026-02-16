#!/usr/bin/env bash
# Wrapper for nixos-infect on DigitalOcean droplets.
# Bakes in static networking config since DHCP doesn't survive infect.
#
# Usage: ssh root@<droplet-ip> < bin/do-nixos-infect.sh
# Or:    ssh root@<droplet-ip> 'bash -s' < bin/do-nixos-infect.sh
#
# Prerequisites: droplet must be running Ubuntu/Debian with SSH access.
set -euo pipefail

echo "=== DigitalOcean NixOS Infect Wrapper ==="

# Auto-detect network config
IP=$(ip -4 addr show eth0 | grep -oP 'inet \K[\d.]+')
PREFIX=$(ip -4 addr show eth0 | grep -oP 'inet [\d.]+/\K\d+')
GW=$(ip route | grep default | awk '{print $3}')

echo "Detected: IP=$IP/$PREFIX GW=$GW"

# Create networking module that nixos-infect will import
cat > /etc/nixos-networking.nix << EOF
{ ... }: {
  networking.useDHCP = false;
  networking.interfaces.eth0.ipv4.addresses = [{
    address = "$IP";
    prefixLength = $PREFIX;
  }];
  networking.defaultGateway = "$GW";
  networking.nameservers = [ "67.207.67.2" "67.207.67.3" ];
}
EOF

echo "Networking config written to /etc/nixos-networking.nix"
cat /etc/nixos-networking.nix

echo ""
echo "=== Running nixos-infect (NO_REBOOT=1) ==="

curl -sL https://raw.githubusercontent.com/elitak/nixos-infect/master/nixos-infect \
  | NIXOS_IMPORT=/etc/nixos-networking.nix \
    NIX_CHANNEL=nixos-24.11 \
    NO_REBOOT=1 \
    bash -x

echo ""
echo "=== Installing bootloader and rebooting ==="
NIXOS_INSTALL_BOOTLOADER=1 /nix/var/nix/profiles/system/bin/switch-to-configuration boot
echo "Rebooting in 3 seconds..."
sleep 3
reboot

# Hardware configuration placeholder for ene (DigitalOcean droplet)
# This file will be replaced by nix-infect output after deployment.
#
# After running nix-infect on the droplet:
# 1. Copy /etc/nixos/hardware-configuration.nix from the droplet
# 2. Replace this file with that content
# 3. Commit the changes
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_scsi" "ahci" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "virtio_net" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/vda1";
    fsType = "ext4";
  };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}

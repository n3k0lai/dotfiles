# Hardware configuration for chat (home server)
# This file will be replaced by nixos-generate-config output after deployment.
#
# After installing NixOS on the physical server:
# 1. Run: nixos-generate-config --show-hardware-config
# 2. Replace this file with that content
# 3. Commit the changes
{ config, lib, pkgs, modulesPath, ... }:

{
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];  # Intel KVM for Windows VM
  boot.extraModulePackages = [ ];

  # Root filesystem - update UUID after install
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/REPLACE-WITH-ROOT-UUID";
    fsType = "ext4";
  };

  # EFI boot partition - update UUID after install
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/REPLACE-WITH-BOOT-UUID";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  # Svalbard storage handled by modules/hardware/svalbard.nix

  swapDevices = [ ];

  # Intel CPU microcode updates
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}

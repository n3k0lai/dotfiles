# Hardware configuration for blade (Razer Blade Stealth 13" 2019, RZ09-0281x)
# Captured from the live dao/blade disk on 2026-08-17.
#
# Generation 11 hung waiting for /dev/disk/by-label/{nixos,boot}.
# This NVMe has no those labels — always use UUIDs.
#
# Regen only if partitions change:
#   sudo nixos-generate-config --show-hardware-config > hosts/blade-hardware.nix
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "nvme"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/bc13e649-bf2e-42da-8a97-5d51bf0bc4f8";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/9D84-820B";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  swapDevices = [
    { device = "/dev/disk/by-uuid/6291cf27-0d2f-41bd-a9ae-3f4fc448084e"; }
  ];

  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}

# pati0 hardware — Raspberry Pi 4 Model B Rev 1.2, 64G SD (live probe 2026-08-11)
# Root label NIXOS_SD; FIRMWARE vfat for Pi boot firmware + config.txt overlays.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "usbhid"
    "usb_storage"
    "vc4"
    "pcie_brcmstb"
    "reset-raspberrypi"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  # Stock NixOS sd-card layout (probed on device).
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
  };

  # Pi firmware partition (config.txt, overlays, start*.elf).
  fileSystems."/boot/firmware" = {
    device = "/dev/disk/by-label/FIRMWARE";
    fsType = "vfat";
    options = [
      "nofail"
      "x-systemd.device-timeout=10"
    ];
  };

  swapDevices = [ ];

  networking.useDHCP = lib.mkDefault true;
  # Live iface names from probe: end0 (eth), wlan0
  networking.interfaces.end0.useDHCP = lib.mkDefault true;
  networking.interfaces.wlan0.useDHCP = lib.mkDefault true;

  hardware.enableRedistributableFirmware = true;
}

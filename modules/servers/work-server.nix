# Windows guest host: libvirt/QEMU + SPICE USB + optional VFIO.
# Used by blade (Forscan / OBD) and any future work VM.
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.modules.servers.workVm;
in {
  options.modules.servers.workVm = {
    enable = mkEnableOption "Windows VM host (libvirt/QEMU)";

    memoryMB = mkOption {
      type = types.int;
      default = 8192;
      description = "Suggested guest RAM in MB (documented; set in the domain XML)";
    };

    cores = mkOption {
      type = types.int;
      default = 4;
      description = "Suggested guest vCPU count (documented; set in the domain XML)";
    };

    # IOMMU on, but do not bind any host GPU to vfio-pci.
    iommu = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Intel VT-d (needed before any PCI/USB-controller passthrough)";
    };

    gpuPassthrough = mkOption {
      type = types.bool;
      default = false;
      description = "Load vfio-pci. Bind specific IDs in the host config — do not enable blindly on Optimus.";
    };
  };

  config = mkIf cfg.enable {
    programs.virt-manager.enable = true;
    security.polkit.enable = true;

    virtualisation.libvirtd = {
      enable = true;
      onBoot = "ignore";
      onShutdown = "shutdown";
      qemu = {
        package = pkgs.qemu_kvm;
        runAsRoot = true;
        # OVMF/UEFI firmware ships with QEMU now; qemu.ovmf was removed.
        swtpm.enable = true;
      };
    };

    # Click-attach USB from virt-manager / spicy (OBD adapters, Flipper, etc.)
    virtualisation.spiceUSBRedirection.enable = true;

    users.users.nicho.extraGroups = [ "libvirtd" "kvm" ];

    # Windows guests often hit ignored MSRs; don't fatal them.
    boot.extraModprobeConfig = ''
      options kvm ignore_msrs=1
      options kvm report_ignored_msrs=0
    '';

    boot.kernelParams = mkIf cfg.iommu [
      "intel_iommu=on"
      "iommu=pt"
    ];

    boot.kernelModules = mkIf cfg.gpuPassthrough [
      "vfio"
      "vfio_iommu_type1"
      "vfio_pci"
    ];

    networking.firewall.trustedInterfaces = [ "virbr0" ];

    environment.systemPackages = with pkgs; [
      virt-viewer
      spice-gtk
      spice-protocol
      usbredir
      virtio-win
      swtpm
    ];

    # virt-manager "CDROM" → /etc/virtio-win  (virtio guest drivers)
    environment.etc."virtio-win".source = pkgs.virtio-win;
  };
}

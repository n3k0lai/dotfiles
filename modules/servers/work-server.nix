# Windows VM module for work using libvirt/QEMU
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.modules.servers.workVm;
in {
  options.modules.servers.workVm = {
    enable = mkEnableOption "Windows VM for work";

    memoryMB = mkOption {
      type = types.int;
      default = 8192;
      description = "Memory allocated to the VM in MB";
    };

    cores = mkOption {
      type = types.int;
      default = 4;
      description = "Number of CPU cores allocated to the VM";
    };

    gpuPassthrough = mkOption {
      type = types.bool;
      default = false;
      description = "Enable GPU passthrough (requires IOMMU setup)";
    };
  };

  config = mkIf cfg.enable {
    # Libvirt virtualization
    virtualisation.libvirtd = {
      enable = true;
      qemu = {
        package = pkgs.qemu_kvm;
        runAsRoot = true;

        # UEFI support for Windows 11
        ovmf = {
          enable = true;
          packages = [ pkgs.OVMFFull.fd ];
        };

        # TPM support for Windows 11
        swtpm.enable = true;
      };
    };

    # Enable spice for VM display
    virtualisation.spiceUSBRedirection.enable = true;

    # User groups for virtualization
    users.users.nicho.extraGroups = [ "libvirtd" "kvm" ];

    # Management tools
    environment.systemPackages = with pkgs; [
      virt-manager
      virt-viewer
      spice-gtk
      win-virtio  # VirtIO drivers for Windows
    ];

    # GPU passthrough configuration (disabled by default)
    boot.kernelParams = mkIf cfg.gpuPassthrough [
      "intel_iommu=on"
      "iommu=pt"
    ];

    boot.kernelModules = mkIf cfg.gpuPassthrough [
      "vfio"
      "vfio_iommu_type1"
      "vfio_pci"
      "vfio_virqfd"
    ];
  };
}

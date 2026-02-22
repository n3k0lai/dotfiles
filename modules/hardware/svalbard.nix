# Svalbard RAID Array Auto-Mount Module
{ config, lib, pkgs, ... }:

with lib;

{
  options.hardware.svalbard = {
    enable = mkEnableOption "Svalbard USB RAID array auto-mounting";

    uuid = mkOption {
      type = types.str;
      default = "223E80423E8010C9";
      description = "UUID of the RAID array filesystem";
      example = "12345678-1234-1234-1234-123456789012";
    };

    mountPoint = mkOption {
      type = types.str;
      default = "/mnt/svalbard";
      description = "Mount point for the RAID array";
    };

    fsType = mkOption {
      type = types.str;
      default = "ntfs";
      description = "Filesystem type of the RAID array";
    };

    devicePath = mkOption {
      type = types.str;
      default = "";
      description = "Device path (e.g., /dev/md0) if using software RAID";
    };

    usbVendor = mkOption {
      type = types.str;
      default = "1058";
      description = "USB vendor ID of the RAID enclosure";
    };

    usbProduct = mkOption {
      type = types.str;
      default = "25f6";
      description = "USB product ID of the RAID enclosure";
    };

    readOnly = mkOption {
      type = types.bool;
      default = false;
      description = "Mount read-only for safety (use remount for writes)";
    };

    uid = mkOption {
      type = types.int;
      default = 1000;
      description = "UID for NTFS mount ownership";
    };

    gid = mkOption {
      type = types.int;
      default = 100;
      description = "GID for NTFS mount ownership";
    };

    assembleRaid = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to assemble software RAID before mounting (not needed for hardware RAID)";
    };

    raidDevices = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "List of device paths to assemble into RAID (not needed for hardware RAID)";
      example = [ "/dev/sda" "/dev/sdb" ];
    };
  };

  config = mkIf config.hardware.svalbard.enable {
    # Ensure necessary packages are available
    environment.systemPackages = with pkgs; [
      ntfs3g  # For NTFS support
      udev
    ];

    # Create mount point
    systemd.tmpfiles.rules = [
      "d ${config.hardware.svalbard.mountPoint} 0755 root root -"
    ];

    # udev rule to detect the USB RAID enclosure
    services.udev.extraRules = ''
      # Svalbard RAID Array
      ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="${config.hardware.svalbard.usbVendor}", ATTR{idProduct}=="${config.hardware.svalbard.usbProduct}", TAG+="systemd", ENV{SYSTEMD_WANTS}="svalbard-mount.service"
    '';

    # Systemd service to mount the RAID array
    systemd.services.svalbard-mount = {
      description = "Mount Svalbard RAID Array";
      after = [ "local-fs.target" ];
      # Start on boot if device is present
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = let
          mountScript = pkgs.writeScript "svalbard-mount" ''
            #!${pkgs.bash}/bin/bash
            set -e

            MOUNT_POINT="${config.hardware.svalbard.mountPoint}"

            # Wait for device to be available
            DEVICE=""
            if [ -n "${config.hardware.svalbard.uuid}" ]; then
              DEVICE="/dev/disk/by-uuid/${config.hardware.svalbard.uuid}"
            elif [ -n "${config.hardware.svalbard.devicePath}" ]; then
              DEVICE="${config.hardware.svalbard.devicePath}"
            else
              echo "No device specified for Svalbard"
              exit 1
            fi

            # Check if device exists, exit gracefully if not (for boot-time startup)
            if [ ! -b "$DEVICE" ]; then
              echo "Device $DEVICE not found, skipping mount"
              exit 0
            fi

            # Check if already mounted
            if ${pkgs.util-linux}/bin/mountpoint -q "$MOUNT_POINT"; then
              echo "Svalbard already mounted at $MOUNT_POINT"
              exit 0
            fi

            # Mount the filesystem
            echo "Mounting Svalbard RAID array at $MOUNT_POINT"
            MOUNT_OPTS="defaults,nofail,uid=${toString config.hardware.svalbard.uid},gid=${toString config.hardware.svalbard.gid}"
            ${lib.optionalString config.hardware.svalbard.readOnly ''MOUNT_OPTS="$MOUNT_OPTS,ro"''}
            ${pkgs.util-linux}/bin/mount -t ${config.hardware.svalbard.fsType} -o "$MOUNT_OPTS" "$DEVICE" "$MOUNT_POINT"
          '';
        in "${mountScript}";

        ExecStop = let
          unmountScript = pkgs.writeScript "svalbard-unmount" ''
            #!${pkgs.bash}/bin/bash
            MOUNT_POINT="${config.hardware.svalbard.mountPoint}"
            if ${pkgs.util-linux}/bin/mountpoint -q "$MOUNT_POINT"; then
              echo "Unmounting Svalbard RAID array"
              ${pkgs.util-linux}/bin/umount "$MOUNT_POINT"
            fi
          '';
        in "${unmountScript}";
      };
    };

    # The service is now configured to start on boot if device is present
  };
}
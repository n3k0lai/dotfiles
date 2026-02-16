# Samsung USB-C Drive Auto-Mount Module
{ config, lib, pkgs, ... }:

with lib;

{
  options.hardware.sammy = {
    enable = mkEnableOption "Samsung USB-C drive auto-mounting";

    uuid = mkOption {
      type = types.str;
      default = "A9B9-E966";
      description = "UUID of the Samsung drive filesystem";
      example = "12345678-1234-1234-1234-123456789012";
    };

    mountPoint = mkOption {
      type = types.str;
      default = "/mnt/sammy";
      description = "Mount point for the Samsung drive";
    };

    fsType = mkOption {
      type = types.str;
      default = "vfat";
      description = "Filesystem type of the Samsung drive";
    };

    devicePath = mkOption {
      type = types.str;
      default = "";
      description = "Device path if using a specific device";
    };

    usbVendor = mkOption {
      type = types.str;
      default = "04e8";
      description = "USB vendor ID of the Samsung drive";
    };

    usbProduct = mkOption {
      type = types.str;
      default = "6300";
      description = "USB product ID of the Samsung drive";
    };
  };

  config = mkIf config.hardware.sammy.enable {
    # Create mount point
    systemd.tmpfiles.rules = [
      "d ${config.hardware.sammy.mountPoint} 0755 root root -"
    ];

    # udev rule to detect the USB drive
    services.udev.extraRules = ''
      # Samsung USB-C Drive
      ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="${config.hardware.sammy.usbVendor}", ATTR{idProduct}=="${config.hardware.sammy.usbProduct}", TAG+="systemd", ENV{SYSTEMD_WANTS}="sammy-mount.service"
    '';

    # Systemd service to mount the drive
    systemd.services.sammy-mount = {
      description = "Mount Samsung USB-C Drive";
      after = [ "local-fs.target" ];
      # Start on boot if device is present
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = let
          mountScript = pkgs.writeScript "sammy-mount" ''
            #!${pkgs.bash}/bin/bash
            set -e

            MOUNT_POINT="${config.hardware.sammy.mountPoint}"

            # Wait for device to be available
            DEVICE=""
            if [ -n "${config.hardware.sammy.uuid}" ]; then
              DEVICE="/dev/disk/by-uuid/${config.hardware.sammy.uuid}"
            elif [ -n "${config.hardware.sammy.devicePath}" ]; then
              DEVICE="${config.hardware.sammy.devicePath}"
            else
              echo "No device specified for Sammy"
              exit 1
            fi

            # Check if device exists, exit gracefully if not (for boot-time startup)
            if [ ! -b "$DEVICE" ]; then
              echo "Device $DEVICE not found, skipping mount"
              exit 0
            fi

            # Check if already mounted
            if ${pkgs.util-linux}/bin/mountpoint -q "$MOUNT_POINT"; then
              echo "Sammy already mounted at $MOUNT_POINT"
              exit 0
            fi

            # Mount the filesystem
            echo "Mounting Samsung USB-C drive at $MOUNT_POINT"
            ${pkgs.util-linux}/bin/mount -t ${config.hardware.sammy.fsType} "$DEVICE" "$MOUNT_POINT"
          '';
        in "${mountScript}";

        ExecStop = let
          unmountScript = pkgs.writeScript "sammy-unmount" ''
            #!${pkgs.bash}/bin/bash
            MOUNT_POINT="${config.hardware.sammy.mountPoint}"
            if ${pkgs.util-linux}/bin/mountpoint -q "$MOUNT_POINT"; then
              echo "Unmounting Samsung USB-C drive"
              ${pkgs.util-linux}/bin/umount "$MOUNT_POINT"
            fi
          '';
        in "${unmountScript}";
      };
    };
  };
}
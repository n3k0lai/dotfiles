{ config, pkgs, lib, ... }:

# OctoPrint — Web interface for Ender 3 V1
# Printer: Creality Ender 3 V1 (SKR Mini E3 V2.0, BLTouch, Glass Bed)
# Webcam: Logitech BRIO (mounted upside-down)
# Access: Tailscale only (100.0.0.0/8), proxied via octo.comfy.sh (Ene/Caddy)

{
  services.octoprint = {
    enable = true;
    port = 5000;
    host = "0.0.0.0";

    plugins = plugins: with plugins; [
      # Add plugins here as needed, e.g.:
      # themeify
      # bedlevelvisualizer
      # displaylayerprogress
    ];

    extraConfig = {
      # Serial / printer connection
      serial = {
        port = "/dev/ttyACM0";  # SKR Mini E3 V2.0 typically uses ACM
        baudrate = 115200;
        autoconnect = true;
        additionalPorts = [ "/dev/ttyUSB0" ];  # fallback
      };

      # Webcam (Logitech BRIO, mounted upside-down)
      webcam = {
        stream = "http://127.0.0.1:8080/?action=stream";
        snapshot = "http://127.0.0.1:8080/?action=snapshot";
        flipV = true;   # Camera is upside-down
        flipH = false;
      };

      # Printer profile for Ender 3
      printerProfiles = {
        default = "ender3";
      };

      # Access control — first-run wizard will prompt for admin user
      accessControl = {
        enabled = true;
      };

      # Server settings
      server = {
        firstRun = true;
        onlineCheck = {
          enabled = true;
        };
      };
    };
  };

  # mjpg-streamer for webcam feed
  systemd.services.mjpg-streamer = {
    description = "MJPG-Streamer for OctoPrint webcam (Logitech BRIO)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];

    serviceConfig = {
      ExecStart = ''
        ${pkgs.mjpg-streamer}/bin/mjpg_streamer \
          -i "input_uvc.so -d /dev/video0 -r 1280x720 -f 30 -rot 180" \
          -o "output_http.so -p 8080 -w ${pkgs.mjpg-streamer}/share/mjpg-streamer/www -l 127.0.0.1"
      '';
      User = "octoprint";
      SupplementaryGroups = [ "video" ];
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  # Ensure octoprint user has access to serial + video devices
  users.users.octoprint.extraGroups = [ "dialout" "video" ];

  # udev rule: stable symlink for Ender 3 serial port
  services.udev.extraRules = ''
    # Ender 3 with SKR Mini E3 V2.0 (STM32 USB)
    SUBSYSTEM=="tty", ATTRS{idVendor}=="1d50", ATTRS{idProduct}=="614e", SYMLINK+="ender3", MODE="0660", GROUP="dialout"
  '';

  # Firewall: allow OctoPrint + mjpg-streamer on Tailscale only
  networking.firewall.interfaces."tailscale0" = {
    allowedTCPPorts = [ 5000 ];
  };
}

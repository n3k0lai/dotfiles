# pati0 — patio Raspberry Pi 4 edge node for Rook's Home Assistant
#
# Role: NOT a second HA brain. Rook = primary HA + Matter + MQTT.
# pati0 handles:
#   - Pi CSI camera → still/stream toward rook HA
#   - patio fan-lights (BT/IR shim) → MQTT entities on rook
#   - optional meshtastic later (module not imported until hash filled)
#
# Network: LAN 192.168.68.60 (DHCP) · MAC dc:a6:32:5b:69:28 · Tailscale TBD
# MQTT / HA: rook Tailscale 100.114.138.5
#
# Build / switch ON the Pi (aarch64):
#   sudo nixos-rebuild switch --flake /path/to/dotfiles#pati0
# Cross-eval from rook/kiss is OK; full build needs aarch64 or binfmt.
{ config, pkgs, lib, ... }:

let
  rookTs = "100.114.138.5";
  rookMqttHost = rookTs;
  rookHaUrl = "http://${rookTs}:8123";

  # SSH keys that already work on the stock image (hermes@rook + nicholai).
  sshKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJntuxxz6/6FmMQyOxIDTF36Ql4ZDfZymAtPTGAGqmFO"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE4uva6ZuYgjkbSvjVwu1t9A0hReGWmwmoIpbCKxDfP/ nicholai@comfy.sh"
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDYabFqlObrdCGfwz4kFCcKXEpWVPtG6qMrUD5cxH6+/tIZJjMGnRyYm/rbScbz0Zzy0w8CKtBFuJkAm3mTVfczl8O80mIEXnV8Ue1reSastDiI/DMhUKmqtPruIEd1EBtsBkY49tmUl6zM1yfwqSZl+ecS0E4F7qt26wpIbMTaP8db+38s7OmTOvRMqe+TgaTUvGR51xTORIuOWgw6bJZgbm8sALwi2KdMwXAbUb/yK8KMdaThavanxsQkj2C0ORB/4toj1hBqk2umDlFx6GqGIFxcUmMkaCYGmXbHVFLsnTUgk0Uf1B4/fqfzmFygZ4LU1CRVTYHBIrf2+7BCj18tozf9t6ebq1A4JCkC0UkGZ+q2Yv0++JVkjgphdyE9u8nTeWl0EgQM4F8qcTPRePv3nOqLrQu9T+OMDLUTlDIc0cRLDAffrDkn/UNL4QG4rFJlbV5Bgtyg21JPelO5LEH2ph2V19T785PUxxXE72uMCYvGNzoDj5JLJv+MGSkH8gS8TPy+Ret5FkyeEtWtX+iMRCuhf8MCUwW2/qslwBRRqxioDyNHhN4t74B8XH+oJWGI0bnC+R/P5b5U0YVqy2zePKjt393/HKMlzCYwD9nN/1akoN6PsjjaYl93VMVm07K0Qryh9TxEaGuH1TCdFjcKyAvoLs+/ParxSy20PZSY3Q== rook@comfy.sh"
  ];

  # Camera Module v2 (IMX219) is the default guess — change if yours is v1/v3.
  # v1 = ov5647 · v2 = imx219 · v3 = imx708
  cameraOverlay = "imx219";

  fans = [
    {
      name = "patio-fan-1";
      mac = "D0:39:72:XX:XX:XX"; # replace after first BT scan
      lightEntity = "light.patio_fan_1_light";
      fanEntity = "fan.patio_fan_1";
    }
    {
      name = "patio-fan-2";
      mac = "D0:39:72:YY:YY:YY";
      lightEntity = "light.patio_fan_2_light";
      fanEntity = "fan.patio_fan_2";
    }
  ];
in
{
  networking.hostName = "pati0";
  networking.domain = "lan";

  # --- boot: RPi vendor kernel so CSI overlays / camera_auto_detect work ---
  # Stock sd-card image used mainline + u-boot FDTDIR; CSI stayed disabled.
  boot.kernelPackages = pkgs.linuxPackages_rpi4;
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;
  boot.consoleLogLevel = lib.mkDefault 7;

  # Write camera lines into the firmware config that the Pi GPU bootloader reads.
  # generic-extlinux still boots the NixOS kernel; start.elf applies overlays first.
  system.activationScripts.pati0FirmwareCamera = {
    deps = [ ];
    text = ''
      CFG=/boot/firmware/config.txt
      if [ -f "$CFG" ]; then
        if ! grep -q 'pati0-camera' "$CFG" 2>/dev/null; then
          printf '\n# pati0-camera (managed by hosts/pati0.nix)\n' >> "$CFG"
          printf 'camera_auto_detect=1\n' >> "$CFG"
          printf 'dtoverlay=${cameraOverlay}\n' >> "$CFG"
          printf 'gpu_mem=128\n' >> "$CFG"
        fi
      fi
    '';
  };

  # Load sensor + unicam after boot (harmless if overlay already bound them).
  boot.kernelModules = [
    "bcm2835_unicam"
    "imx219"
    "ov5647"
  ];

  # CMA for libcamera / ISP (default often too tight under load).
  boot.kernelParams = [
    "console=ttyS0,115200n8"
    "console=ttyAMA0,115200n8"
    "console=tty0"
    "cma=256M"
  ];

  # config.txt dtoverlay is not enough under u-boot+FDTDIR — apply rpi kernel overlay at boot.
  systemd.services.pati0-camera-overlay = {
    description = "Apply ${cameraOverlay} CSI device-tree overlay";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "pati0-camera-overlay" ''
        set -e
        DTBS=/run/current-system/dtbs/overlays
        BIN=${pkgs.libraspberrypi}/bin/dtoverlay
        if [ -x "$BIN" ] && [ -f "$DTBS/${cameraOverlay}.dtbo" ]; then
          "$BIN" -d "$DTBS" ${cameraOverlay} || true
        fi
      '';
    };
  };

  # libcamera needs dma_heap + vcsm accessible to video group
  services.udev.extraRules = ''
    SUBSYSTEM=="dma_heap", GROUP="video", MODE="0660"
    KERNEL=="vcsm-cma", GROUP="video", MODE="0660"
  '';

  environment.sessionVariables = {
    # Helps IPA modules resolve under Nix store paths
    LIBCAMERA_IPA_MODULE_PATH = "${pkgs.libcamera}/lib/libcamera";
  };

  # --- users / ssh ---
  users.mutableUsers = true;
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "video"
      "dialout"
      "networkmanager"
    ];
    openssh.authorizedKeys.keys = sshKeys;
  };
  users.users.root.openssh.authorizedKeys.keys = sshKeys;

  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  # --- networking ---
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22
      8081 # patio MJPEG for Home Assistant (LAN)
    ];
  };

  services.tailscale = {
    enable = true;
    openFirewall = true;
    # first boot: sudo tailscale up --ssh --hostname=pati0
  };

  networking.networkmanager.enable = false; # stick to dhcpcd like stock image
  networking.useNetworkd = false;

  # --- bluetooth (patio fans) ---
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  services.blueman.enable = false;

  # --- camera + edge packages (cam.nix / fans.nix folded in) ---
  environment.systemPackages = with pkgs; [
    git
    tmux
    htop
    usbutils
    pciutils
    ffmpeg
    v4l-utils
    libcamera
    mosquitto
    bluez
    i2c-tools
    libraspberrypi
    raspberrypi-eeprom
  ]
  ++ lib.optionals (pkgs ? rpicam-apps) [ pkgs.rpicam-apps ]
  ++ lib.optionals (pkgs ? rpicam-apps-lite) [ pkgs.rpicam-apps-lite ];

  # Rook pointers (MQTT / HA) — no secrets
  environment.etc."pati0/rook.env".text = ''
    ROOK_MQTT_HOST=${rookMqttHost}
    ROOK_MQTT_PORT=1883
    ROOK_HA_URL=${rookHaUrl}
    ROOK_TAILSCALE_IP=${rookTs}
    ROOK_TS_DNS=rook.bushbaby-mercat.ts.net
    PATI0_CAMERA_OVERLAY=${cameraOverlay}
  '';

  # Fan inventory (folded from former fans.nix). fanctl daemon TBD (bleak).
  # Amazon Fanbulous-class outdoor fans — BT app + IR; Pi shims via MQTT later.
  environment.etc."pati0/fans.json".text = builtins.toJSON {
    mqtt = {
      host = rookMqttHost;
      port = 1883;
    };
    ha_url = rookHaUrl;
    fans = fans;
  };

  # Camera device contract + HA stream URL
  environment.etc."pati0/cameras.json".text = builtins.toJSON {
    rook_ha_url = rookHaUrl;
    mjpeg_url = "http://192.168.68.60:8081/stream.mjpg";
    devices = [
      {
        name = "patio";
        device = "/dev/video0";
        overlay = cameraOverlay;
      }
    ];
  };

  # MJPEG HTTP stream for rook HA (generic/ffmpeg camera).
  # cam (libcamera) → FIFO → ffmpeg mpjpeg listen on :8081
  # Prefer this over libcamerify+V4L when CMA is tight; still wants cma=256M.
  systemd.services.pati0-mjpeg = {
    description = "Patio IMX219 MJPEG stream (HA)";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "pati0-camera-overlay.service"
    ];
    wants = [ "pati0-camera-overlay.service" ];
    path = with pkgs; [
      coreutils
      libcamera
      ffmpeg
      bash
    ];
    serviceConfig = {
      Type = "simple";
      User = "nixos";
      Group = "video";
      SupplementaryGroups = [ "video" ];
      Restart = "always";
      RestartSec = "5";
      RuntimeDirectory = "pati0-mjpeg";
      # Camera + network need real devices
      PrivateDevices = false;
      ProtectHome = true;
      NoNewPrivileges = true;
      MemoryDenyWriteExecute = false;
      Environment = [
        "LIBCAMERA_IPA_MODULE_PATH=${pkgs.libcamera}/lib/libcamera"
      ];
      ExecStart = pkgs.writeShellScript "pati0-mjpeg" ''
        set -euo pipefail
        export LIBCAMERA_IPA_MODULE_PATH=${pkgs.libcamera}/lib/libcamera
        FIFO=/run/pati0-mjpeg/cam.fifo
        # Loop: ffmpeg -listen 1 exits after each client (HA reconnects OK).
        while true; do
          rm -f "$FIFO"
          mkfifo "$FIFO"
          ${pkgs.libcamera}/bin/cam -c1 --capture=0 \
            --stream width=640,height=480,role=viewfinder \
            --file="$FIFO" &
          CAM_PID=$!
          # Give cam a moment; ffmpeg blocks on accept until HA/curl connects
          ${pkgs.ffmpeg}/bin/ffmpeg -hide_banner -loglevel warning \
            -f rawvideo -pix_fmt rgba -video_size 640x480 -framerate 12 \
            -thread_queue_size 64 -i "$FIFO" \
            -an -c:v mjpeg -q:v 7 \
            -f mpjpeg -boundary_tag ffmpeg \
            -listen 1 http://0.0.0.0:8081/stream.mjpg \
            || true
          kill "$CAM_PID" 2>/dev/null || true
          wait "$CAM_PID" 2>/dev/null || true
          sleep 1
        done
      '';
    };
  };

  # --- nix ---
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [
      "root"
      "nixos"
    ];
  };
  nixpkgs.config.allowUnfree = true;

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  # Lean edge — no HA Core, no Matter server, no Hermes.
  documentation.nixos.enable = false;

  system.stateVersion = "25.05";
}

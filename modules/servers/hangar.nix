# Droneforge Nimbus hangar on Rook (USB module + localhost ZeroMQ).
{ config, pkgs, lib, ... }:

let
  cfg = config.modules.servers.hangar;

  nimbusos-sdk = pkgs.python3Packages.buildPythonPackage rec {
    pname = "nimbusos-sdk";
    version = "0.1.9";
    pyproject = true;
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/source/n/nimbusos-sdk/nimbusos_sdk-${version}.tar.gz";
      hash = "sha256-nC4RTWx+Cuo0sI8yApzdhC/CB50nQxfdB+ly6bfINT0=";
    };
    build-system = with pkgs.python3Packages; [
      setuptools
      wheel
    ];
    dependencies = with pkgs.python3Packages; [
      flatbuffers
      pyzmq
    ];
    pythonRelaxDeps = [ "flatbuffers" ];
    doCheck = false;
  };

  hangarHealth = pkgs.writeShellScriptBin "hangar-health" ''
    set -euo pipefail
    export DF_ZMQ_PUB_ENDPOINT="${cfg.pubEndpoint}"
    export DF_ZMQ_SUB_ENDPOINT="${cfg.subEndpoint}"
    echo "Checking NimbusOS telemetry on ${cfg.subEndpoint} ..."
    ${nimbusos-sdk}/bin/nimbusos-subscribe telemetry --limit 1 --timeout 5 \
      --sub-endpoint "${cfg.subEndpoint}"
    echo "hangar-health: OK"
  '';

  # Extract NimbusOS AppImage from the official .deb into /var/lib/nimbus.
  nimbusInstall = pkgs.writeShellScriptBin "hangar-install-nimbus" ''
    set -euo pipefail
    DEB="''${1:-}"
    if [ -z "$DEB" ] || [ ! -f "$DEB" ]; then
      echo "Usage: hangar-install-nimbus /path/to/NimbusOS-*-amd64.deb" >&2
      echo "Download from: https://github.com/droneforge/NimbusOS-Desktop/releases" >&2
      exit 1
    fi
    DEST="${cfg.stateDir}"
    WORK=$(mktemp -d)
    trap 'rm -rf "$WORK"' EXIT
    ${pkgs.dpkg}/bin/dpkg-deb -x "$DEB" "$WORK"
    APPIMAGE=$(find "$WORK" -name '*.AppImage' -type f | head -1)
    if [ -z "$APPIMAGE" ]; then
      echo "No AppImage found inside $DEB" >&2
      exit 1
    fi
    install -d -m 0755 -o nimbus -g nimbus "$DEST"
    install -m 0755 -o nimbus -g nimbus "$APPIMAGE" "$DEST/NimbusOS.AppImage"
    echo "Installed $DEST/NimbusOS.AppImage"
    if command -v systemctl >/dev/null 2>&1; then
      systemctl reset-failed nimbusos.service 2>/dev/null || true
      systemctl start nimbusos.service
      echo "Started nimbusos.service"
    else
      echo "Start with: systemctl start nimbusos"
    fi
  '';

  nimbusRunner = pkgs.writeShellScript "nimbusos-runner" ''
    set -euo pipefail
    APPIMAGE="${cfg.stateDir}/NimbusOS.AppImage"
    # systemd ConditionPathExists should skip us when missing; belt-and-suspenders.
    if [ ! -x "$APPIMAGE" ]; then
      echo "NimbusOS not installed. Run: hangar-install-nimbus /path/to/NimbusOS.deb" >&2
      exit 1
    fi
    # Electron apps need a writable config dir; keep state under /var/lib/nimbus.
    export HOME="${cfg.stateDir}"
    export XDG_CONFIG_HOME="${cfg.stateDir}/.config"
    export XDG_DATA_HOME="${cfg.stateDir}/.local/share"
    mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"
    exec "$APPIMAGE" --no-sandbox "$@"
  '';

in {
  options.modules.servers.hangar = {
    enable = lib.mkEnableOption "Droneforge Nimbus hangar (NimbusOS + SDK on Rook)";

    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/nimbus";
      description = "Directory for NimbusOS AppImage and runtime state";
    };

    pubEndpoint = lib.mkOption {
      type = lib.types.str;
      default = "tcp://127.0.0.1:7771";
      description = "ZeroMQ publish endpoint for NimbusOS commands";
    };

    subEndpoint = lib.mkOption {
      type = lib.types.str;
      default = "tcp://127.0.0.1:7772";
      description = "ZeroMQ subscribe endpoint for NimbusOS telemetry";
    };

    requireConfirmation = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Hangar MCP refuses arm/takeoff without explicit confirmation (phase 4)";
    };

    usbVendorId = lib.mkOption {
      type = lib.types.str;
      default = "10c4";
      description = "USB vendor ID for Nimbus serial device (Silicon Labs CP210x default; verify with udevadm)";
    };

    usbProductId = lib.mkOption {
      type = lib.types.str;
      default = "ea60";
      description = "USB product ID for Nimbus serial device";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.nimbus = {
      isSystemUser = true;
      group = "nimbus";
      description = "NimbusOS / Droneforge hangar service";
      home = cfg.stateDir;
      createHome = true;
    };
    users.groups.nimbus = { };

    # Dialout for serial telemetry if Nimbus exposes a tty device.
    users.users.nimbus.extraGroups = [ "dialout" ];

    services.udev.extraRules = lib.mkAfter ''
      # Droneforge Nimbus USB module (override vendor/product in rook-local.nix if needed)
      SUBSYSTEM=="usb", ATTR{idVendor}=="${cfg.usbVendorId}", ATTR{idProduct}=="${cfg.usbProductId}", TAG+="uaccess", GROUP="dialout"
      SUBSYSTEM=="tty", ATTRS{idVendor}=="${cfg.usbVendorId}", ATTRS{idProduct}=="${cfg.usbProductId}", SYMLINK+="nimbus", MODE="0660", GROUP="dialout"
    '';

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0755 nimbus nimbus -"
      "d ${cfg.stateDir}/.config 0755 nimbus nimbus -"
      "d ${cfg.stateDir}/.local/share 0755 nimbus nimbus -"
    ];

    # AppImage is installed out-of-band (hangar-install-nimbus). Until then the
    # unit must not crash-loop and must not fail nixos-rebuild switch.
    systemd.services.nimbusos = {
      description = "Droneforge NimbusOS (DF1 + ZeroMQ bridge)";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      unitConfig = {
        ConditionPathExists = "${cfg.stateDir}/NimbusOS.AppImage";
        # If the AppImage exists but keeps dying, don't thrash forever.
        StartLimitIntervalSec = 300;
        StartLimitBurst = 5;
      };
      serviceConfig = {
        Type = "simple";
        ExecStart = nimbusRunner;
        Restart = "on-failure";
        RestartSec = 30;
        User = "nimbus";
        Group = "nimbus";
        WorkingDirectory = cfg.stateDir;
        # ZMQ binds localhost only — never expose to tailnet.
        Environment = [
          "DF_ZMQ_PUB_ENDPOINT=${cfg.pubEndpoint}"
          "DF_ZMQ_SUB_ENDPOINT=${cfg.subEndpoint}"
        ];
      };
    };

    # Manual smoke test only — do not gate boot on Nimbus hardware presence.
    systemd.services.hangar-health = {
      description = "Verify NimbusOS telemetry is reachable";
      after = [ "nimbusos.service" ];
      wants = [ "nimbusos.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${hangarHealth}/bin/hangar-health";
        User = "nimbus";
      };
    };

    environment.systemPackages = [
      nimbusos-sdk
      hangarHealth
      nimbusInstall
    ];

    environment.sessionVariables = lib.mkIf config.modules.servers.hermes.enable {
      DF_ZMQ_PUB_ENDPOINT = cfg.pubEndpoint;
      DF_ZMQ_SUB_ENDPOINT = cfg.subEndpoint;
    };

    systemd.services.hermes-agent = lib.mkIf config.modules.servers.hermes.enable {
      environment = {
        DF_ZMQ_PUB_ENDPOINT = cfg.pubEndpoint;
        DF_ZMQ_SUB_ENDPOINT = cfg.subEndpoint;
        HANGAR_REQUIRE_CONFIRMATION = lib.boolToString cfg.requireConfirmation;
      };
    };
  };
}
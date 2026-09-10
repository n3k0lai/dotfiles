# Clicks Power Keyboard (BLE 5.4 HID)
#
# Pairing is per Bluetooth adapter — BlueZ link keys cannot be copied from
# kiss to rook. Pair each host on its own channel, then `clicks connect`.
#
# Keyboard:
#   Pair/switch: hold Power + a number key (1-9) until the LED flashes
#   Clear slot:  connect to that channel, then SYM+0
#   First boot:  power on and slide open (pairs as Clicks Power Keyboard-1)
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.hardware.clicks;

  deviceType = types.submodule {
    options = {
      name = mkOption {
        type = types.str;
        default = "Clicks Power Keyboard";
        description = "Advertised Bluetooth name (channel suffix is ok)";
      };
      address = mkOption {
        type = types.str;
        description = "Bluetooth identity address from `bluetoothctl info`";
        example = "AA:BB:CC:DD:EE:FF";
      };
      channel = mkOption {
        type = types.ints.between 1 9;
        description = "Power Keyboard channel (Power + this number)";
      };
      host = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "NixOS hostname this pairing belongs to";
      };
    };
  };

  devicesText = concatMapStringsSep "\n" (d:
    "${d.address}|${d.name}|${toString d.channel}|${if d.host == null then "" else d.host}"
  ) cfg.devices;

  channelsText = concatStringsSep "\n"
    (mapAttrsToList (host: ch: "${host}=${toString ch}") cfg.channels);
in {
  options.hardware.clicks = {
    enable = mkEnableOption "Clicks Power Keyboard Bluetooth support";

    devices = mkOption {
      type = types.listOf deviceType;
      default = [ ];
      description = ''
        Known pairings. Fill `address` after the first successful pair
        (`bluetoothctl info` → Identity Address / Device address).
      '';
    };

    channels = mkOption {
      type = types.attrsOf (types.ints.between 1 9);
      default = {
        kiss = 9;
        rook = 3;
      };
      description = ''
        Suggested Power Keyboard channel per host. Channel 1 is left for a
        phone. Pairing still has to be done once on each adapter.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Intel AX200 (kiss) / Intel BT USB (rook) firmware
    hardware.enableRedistributableFirmware = true;

    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
      settings = {
        General = {
          # LE HID keyboards (Clicks is BLE 5.4). Android shows HOGP
          # devices that BlueZ hides unless Privacy is off and the input
          # profile accepts unbonded HID.
          Experimental = mkDefault true;
          ControllerMode = mkDefault "dual";
          FastConnectable = true;
          JustWorksRepairing = "always";
          Privacy = "off";
        };
        Policy = {
          AutoEnable = true;
        };
      };
      input = {
        General = {
          ClassicBondedOnly = false;
          UserspaceHID = true;
        };
      };
    };

    environment.etc."clicks/devices".text = devicesText + "\n";
    environment.etc."clicks/channels".text = channelsText + "\n";
    environment.etc."clicks/name-match".text = ''
      Clicks Power Keyboard
      Power Keyboard
      Power Keys
    '';

    environment.systemPackages = [ pkgs.bluez ];
  };
}

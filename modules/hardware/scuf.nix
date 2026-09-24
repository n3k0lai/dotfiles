# SCUF Instinct Pro (Xbox-licensed XInput pad).
#
# Connection, in order of reliability on NixOS:
#   1. USB-C cable — kernel xone (GIP). No extra hardware.
#   2. Xbox Wireless Adapter for Windows (USB dongle) — xone + dongle firmware.
#      Buy Microsoft's adapter, not a 360 receiver and not a Scuf charge dock.
#   3. Bluetooth — xpadneo. Fine as backup; Series-era BT LE can hitch.
#
# Paddle maps live on the pad (SCUF onboard profiles). Set them once in
# SCUF/Xbox Accessories on Windows or an Xbox, then Linux just sees XInput.
{ config, lib, ... }:

with lib;

let
  cfg = config.hardware.scuf;
in {
  options.hardware.scuf = {
    enable = mkEnableOption "SCUF Instinct Pro / Xbox GIP controller support";

    bluetooth = mkOption {
      type = types.bool;
      default = true;
      description = "xpadneo for Bluetooth. Keep on even if you mainly use the dongle.";
    };
  };

  config = mkIf cfg.enable {
    # Wired USB-C + Xbox Wireless dongle (Microsoft "Xbox Wireless Adapter for Windows").
    hardware.xone.enable = true;
    hardware.steam-hardware.enable = true;

    hardware.xpadneo.enable = mkIf cfg.bluetooth true;

    hardware.bluetooth = mkIf cfg.bluetooth {
      enable = true;
      settings.General = {
        ControllerMode = "dual";
        # Clicks sets this to "always" for the BLE keyboard. mkDefault lets
        # that win when both modules are on; confirm remains the pad default.
        JustWorksRepairing = mkDefault "confirm";
        Experimental = true;
      };
    };
  };
}

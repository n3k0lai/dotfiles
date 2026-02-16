{ config, lib, pkgs, ... }:

with lib;

{
  options.hardware.scarlett = {
    enable = mkEnableOption "Focusrite Scarlett Solo USB audio interface";
    
    deviceSerial = mkOption {
      type = types.str;
      default = "Y7J64FH08A3A52";
      description = "Serial number of the Scarlett device";
    };
  };

  config = mkIf config.hardware.scarlett.enable {
    services.pipewire.extraConfig.pipewire."10-scarlett" = {
      "audio.default-sink" = "alsa_output.usb-Focusrite_Scarlett_Solo_USB_${config.hardware.scarlett.deviceSerial}-00.HiFi__Headphones__sink";
      "audio.default-source" = "alsa_input.usb-Focusrite_Scarlett_Solo_USB_${config.hardware.scarlett.deviceSerial}-00.HiFi__Mic1__source";
    };
  };
}

{ config, lib, pkgs, ... }:

with lib;

{
  options.hardware.unicorne = {
    enable = mkEnableOption "Unicorne keyboard";
    
    vendorId = mkOption {
      type = types.str;
      default = "4273";
      description = "USB vendor ID for the Unicorne keyboard";
    };
    
    productId = mkOption {
      type = types.str;
      default = "7563";
      description = "USB product ID for the Unicorne keyboard";
    };
  };

  config = mkIf config.hardware.unicorne.enable {
    services.udev.extraRules = ''
      SUBSYSTEM=="hidraw", ATTRS{idVendor}=="${config.hardware.unicorne.vendorId}", ATTRS{idProduct}=="${config.hardware.unicorne.productId}", MODE="0666"
    '';
  };
}

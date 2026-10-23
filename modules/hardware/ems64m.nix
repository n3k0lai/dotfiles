# EMS GB USB SmartCard 64M flash cart: ems-flasher plus a udev rule
# (TAG+="uaccess") so the logged-in user can talk to it without sudo.
{ config, lib, pkgs, ... }:

with lib;

let
  ems-flasher = pkgs.callPackage ./ems64m/package.nix { };
in
{
  options.hardware.ems64m.enable = mkEnableOption "EMS 64M USB Game Boy flash cart";

  config = mkIf config.hardware.ems64m.enable {
    environment.systemPackages = [ ems-flasher ];
    services.udev.packages = [ ems-flasher ];
  };
}

# ModRetro Chromatic: MR Updater (ChromaticFirmwareUpdater) for firmware
# and Cart Clinic updates over USB-C, plus udev rules so the logged-in
# user can reach the handheld without sudo.
{ config, lib, pkgs, ... }:

with lib;

let
  mr-updater = pkgs.callPackage ./chromatic/package.nix { };
in
{
  options.hardware.chromatic.enable = mkEnableOption "ModRetro Chromatic firmware updater";

  config = mkIf config.hardware.chromatic.enable {
    environment.systemPackages = [ mr-updater ];
    services.udev.packages = [ mr-updater ];
  };
}

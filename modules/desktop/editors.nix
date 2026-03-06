# Editor and development tool modules
# Import what you need per-machine
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.modules.desktop.editors;
in
{
  options.modules.desktop.editors = {
    kicad.enable = mkEnableOption "KiCad EDA suite for schematic/PCB design";
  };

  config = mkMerge [
    (mkIf cfg.kicad.enable {
      environment.systemPackages = with pkgs; [
        kicad         # Schematic + PCB editor
        kicad-symbols # Official symbol libraries
        kicad-footprints
        kicad-packages3d
      ];
    })
  ];
}

# CAD and hardware design tools
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.modules.editors.cad;
in
{
  options.modules.editors.cad = {
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

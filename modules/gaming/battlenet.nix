# Compatibility shim — real module is modules/gaming/bnet.nix (imported from configuration.nix).
{ lib, config, ... }:

{
  options.modules.gaming.battlenet.enable =
    lib.mkEnableOption "Alias for modules.gaming.bnet.enable";

  config = lib.mkIf config.modules.gaming.battlenet.enable {
    modules.gaming.bnet.enable = true;
  };
}

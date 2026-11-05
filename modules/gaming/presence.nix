# DEPRECATED (2026-11-05): Discord presence moved to ~/Code/wowdrawer
# (KissPresence addon + `python -m wowdrawer_helper.presence`).
# This stub keeps `modules.gaming.presence.*` so kiss/blade still evaluate;
# enabling it is a no-op (no packages, no user service, no addon link).
{ config, lib, ... }:

{
  options.modules.gaming.presence = {
    enable = lib.mkEnableOption "Discord presence (moved to wowdrawer; this module is a no-op)";

    wow.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Ignored — presence lives in wowdrawer.";
    };

    minecraft.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Ignored — presence lives in wowdrawer.";
    };
  };

  config = lib.mkIf config.modules.gaming.presence.enable {
    warnings = [
      "modules.gaming.presence is a no-op stub; use ~/Code/wowdrawer (docs/presence.md)."
    ];
  };
}

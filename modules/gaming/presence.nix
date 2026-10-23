# Discord presence for NixOS machines you play on (kiss, blade, later hosts).
# Servers do not import this.
#
#   presence on|off|toggle|status
#   presence hours mon-fri 09:00-17:00
#
# wow-presence is the same command. State stays in ~/.config/kiss-presence.
{ config, lib, pkgs, ... }:

let
  cfg = config.modules.gaming.presence;
  bundle = import ./presence/bundle.nix {
    inherit pkgs;
    wow = cfg.wow.enable;
    minecraft = cfg.minecraft.enable;
  };
in {
  options.modules.gaming.presence = {
    enable = lib.mkEnableOption "Discord presence for World of Warcraft and Minecraft";

    wow.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Publish World of Warcraft. The Forever addon is linked when that install exists.";
    };

    minecraft.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Publish Minecraft while the game process is running.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ bundle.presence bundle.wowPresence ];

    systemd.user.services.presence = {
      description = "Discord presence for World of Warcraft and Minecraft";
      wantedBy = [ "default.target" ];
      after = [ "default.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${bundle.presence}/bin/presence watch";
        Restart = "on-failure";
        RestartSec = 3;
        Environment = [
          "PATH=${lib.makeBinPath bundle.tools}:/run/current-system/sw/bin"
        ] ++ bundle.flags;
      };
    };

    # Link the addon only where Forever is already installed, and drop a
    # hand-written unit that would hide this service.
    home-manager.users.nicho.home.activation.presenceWowAddon = ''
      wow="$HOME/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/_classic_beta_"
      if [ -d "$wow" ]; then
        mkdir -p "$wow/Interface/AddOns"
        ln -sfn ${bundle.addon} "$wow/Interface/AddOns/KissPresence"
      fi
      rm -f "$HOME/.config/systemd/user/presence.service" \
            "$HOME/.config/systemd/user/kiss-presence.service" \
            "$HOME/.config/systemd/user/default.target.wants/presence.service" \
            "$HOME/.config/systemd/user/default.target.wants/kiss-presence.service"
    '';
  };
}

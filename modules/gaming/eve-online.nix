# EVE Online — first-class gaming module (Steam is backup only)
#
# Enable on play hosts (kiss). Does not replace Steam globally; provides a
# dedicated `eve-online` entrypoint that prefers a native/home launcher and
# falls back to Steam AppID 8500 when configured.
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.gaming.eve-online;
  steamAppId = "8500"; # EVE Online on Steam
  eveLauncher = pkgs.writeShellScriptBin "eve-online" ''
    set -euo pipefail
    # Prefer CCP / local Linux install paths if present
    for candidate in \
      "$HOME/Games/eve-online/eve-online" \
      "$HOME/.local/share/eve-online/eve-online" \
      "$HOME/.eve/eve" \
      "/opt/eve-online/eve-online"
    do
      if [ -x "$candidate" ]; then
        exec "$candidate" "$@"
      fi
    done
    ${optionalString cfg.steamBackup ''
    if command -v steam >/dev/null 2>&1; then
      exec steam -applaunch ${steamAppId} "$@"
    fi
    echo "eve-online: no native launcher found and steam backup unavailable." >&2
    echo "Install the EVE Linux client under ~/Games/eve-online or enable Steam." >&2
    exit 1
    ''}
    ${optionalString (!cfg.steamBackup) ''
    echo "eve-online: no native launcher found (steam backup disabled)." >&2
    exit 1
    ''}
  '';
in {
  options.modules.gaming.eve-online = {
    enable = mkEnableOption "EVE Online as a first-class game (dedicated launcher; Steam optional backup)";

    steamBackup = mkOption {
      type = types.bool;
      default = true;
      description = "Fall back to Steam AppID 8500 when no native EVE launcher is installed";
    };
  };

  config = mkIf cfg.enable {
    # Do NOT force modules.gaming.steam.enable — Steam remains optional backup.
    # kiss already enables Steam at the base gaming layer when desired.

    environment.systemPackages = [
      eveLauncher
    ] ++ lib.optional (pkgs ? pyfa) pkgs.pyfa;

    # Friendly desktop entry
    environment.etc."xdg/applications/eve-online.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=EVE Online
      Comment=New Eden — first-class launcher (Steam backup if needed)
      Exec=eve-online
      Terminal=false
      Categories=Game;
      Keywords=eve;mmo;ccp;
    '';
  };
}

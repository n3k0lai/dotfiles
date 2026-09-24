# Battle.net prefix owner — WoW Forever, Warcraft III, W3Champions, WowUp.
#
# Lutris can still *install* Battle.net once. After that, launches go through
# the `bnet` / `bnet-*` wrappers so Proton env, NVIDIA Vulkan ICDs, and the
# XWayland primary display are deterministic instead of Lutris YAML drift.
#
# Prefix (default): ~/Games/battlenet
# Proton: Lutris GE-Proton if present, else nixpkgs proton-ge-bin.
# umu: Lutris runtime if present, else nixpkgs umu-launcher.
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.gaming.bnet;
  protonGe = pkgs.proton-ge-bin.steamcompattool;
  umuPkg = pkgs.umu-launcher;

  nvidiaIcd64 = "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json";
  nvidiaIcd32 = "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.i686.json";

  bnetRun = pkgs.writeShellScriptBin "bnet-run" ''
    set -euo pipefail

    prefix="''${BNET_PREFIX:-$HOME/Games/battlenet}"
    proton="''${PROTONPATH:-}"
    umu="''${UMU_BIN:-}"

    # Pair runtimes. Mixing nixpkgs umu-launcher 1.2.6 with Lutris GE-Proton
    # fails: "Failed to match ... with a container runtime". Lutris umu 1.4.4
    # without an FHS dies: "bwrap: execvp true". Working pair is steam-run +
    # Lutris umu + Lutris GE-Proton.
    umu_pre=()
    lutris_proton="$HOME/.local/share/lutris/runners/proton/ge-proton"
    lutris_umu="$HOME/.local/share/lutris/runtime/umu/umu-run"
    if [ -z "$proton" ] && [ -z "$umu" ] && [ -x "$lutris_proton/proton" ] && [ -x "$lutris_umu" ]; then
      proton="$lutris_proton"
      umu="$lutris_umu"
      if command -v steam-run >/dev/null; then
        umu_pre=(steam-run)
      fi
    else
      if [ -z "$proton" ]; then
        proton="${protonGe}"
      fi
      if [ -z "$umu" ]; then
        umu="${umuPkg}/bin/umu-run"
      fi
    fi

    exe=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --prefix) prefix="$2"; shift 2 ;;
        --proton) proton="$2"; shift 2 ;;
        --) shift; break ;;
        --*) echo "bnet-run: unknown option $1" >&2; exit 2 ;;
        *) exe="$1"; shift; break ;;
      esac
    done
    if [ -z "$exe" ]; then
      echo "usage: bnet-run [--prefix DIR] [--proton DIR] <windows-exe> [args...]" >&2
      exit 2
    fi
    if [ ! -f "$exe" ]; then
      echo "bnet-run: missing $exe" >&2
      echo "Install the game through Battle.net into $prefix first (bnet-setup)." >&2
      exit 1
    fi

    ${optionalString (cfg.primaryOutput != null) ''
      if command -v xrandr >/dev/null && [ -n "''${DISPLAY:-}" ]; then
        xrandr --output ${escapeShellArg cfg.primaryOutput} --primary >/dev/null 2>&1 || true
      fi
    ''}

    export WINEPREFIX="$prefix"
    export PROTONPATH="$proton"
    export GAMEID="''${GAMEID:-umu-battlenet}"
    export STORE="''${STORE:-none}"
    export DISPLAY="''${DISPLAY:-:0}"
    unset WAYLAND_DISPLAY || true
    export QT_QPA_PLATFORM=xcb
    export WINE_SIMULATE_WRITECOPY=1
    export PROTON_ENABLE_WAYLAND=0
    ${optionalString cfg.nvidia ''
      export DXVK_FILTER_DEVICE_NAME="''${DXVK_FILTER_DEVICE_NAME:-NVIDIA}"
      export __GLX_VENDOR_LIBRARY_NAME="''${__GLX_VENDOR_LIBRARY_NAME:-nvidia}"
      if [ -f ${escapeShellArg nvidiaIcd64} ]; then
        export VK_ICD_FILENAMES="${nvidiaIcd64}:${nvidiaIcd32}"
        export VK_DRIVER_FILES="$VK_ICD_FILENAMES"
      fi
    ''}
    ${concatStringsSep "\n" (mapAttrsToList (k: v: ''export ${k}=${escapeShellArg v}'') cfg.extraEnv)}

    exec "''${umu_pre[@]}" "$umu" "$exe" "$@"
  '';

  bnet = pkgs.writeShellScriptBin "bnet" ''
    set -euo pipefail
    prefix="''${BNET_PREFIX:-$HOME/Games/battlenet}"
    exe="$prefix/drive_c/Program Files (x86)/Battle.net/Battle.net.exe"
    exec ${bnetRun}/bin/bnet-run "$exe" "$@"
  '';

  # Always go through Battle.net so Agent is up and we do not start a second
  # umu/Proton on a live prefix (that is what "wofi WC3 crash" was).
  bnetWc3 = pkgs.writeShellScriptBin "bnet-wc3" ''
    set -euo pipefail
    prefix="''${BNET_PREFIX:-$HOME/Games/battlenet}"
    bnet_exe="$prefix/drive_c/Program Files (x86)/Battle.net/Battle.net.exe"
    wc3_exe="$prefix/drive_c/Program Files (x86)/Warcraft III/_retail_/x86_64/Warcraft III.exe"
    if [ ! -f "$wc3_exe" ]; then
      echo "bnet-wc3: Warcraft III is not installed in $prefix" >&2
      exit 1
    fi
    exec ${bnetRun}/bin/bnet-run "$bnet_exe" --exec="launch W3" "$@"
  '';

  bnetWow = pkgs.writeShellScriptBin "bnet-wow" ''
    set -euo pipefail
    prefix="''${BNET_PREFIX:-$HOME/Games/battlenet}"
    exe=""
    for cand in \
      "$prefix/drive_c/Program Files (x86)/World of Warcraft/_classic_beta_/WowB.exe" \
      "$prefix/drive_c/Program Files (x86)/World of Warcraft/_forever_/WowForever.exe" \
      "$prefix/drive_c/Program Files (x86)/World of Warcraft/_forever_/Wow.exe" \
      "$prefix/drive_c/Program Files (x86)/World of Warcraft/_retail_/Wow.exe" \
      "$prefix/drive_c/Program Files (x86)/World of Warcraft/World of Warcraft Launcher.exe"
    do
      if [ -f "$cand" ]; then exe="$cand"; break; fi
    done
    if [ -z "$exe" ]; then
      echo "bnet-wow: no WoW client under $prefix" >&2
      echo "Install World of Warcraft / Forever from Battle.net (bnet)." >&2
      exit 1
    fi
    exec ${bnetRun}/bin/bnet-run "$exe" "$@"
  '';

  bnetW3c = pkgs.writeShellScriptBin "bnet-w3c" ''
    set -euo pipefail
    prefix="''${BNET_PREFIX:-$HOME/Games/battlenet}"
    exe="$prefix/drive_c/Program Files/W3Champions/W3Champions.exe"
    if [ ! -f "$exe" ]; then
      echo "bnet-w3c: W3Champions is not in the prefix yet." >&2
      echo "1. Launch Battle.net with: bnet" >&2
      echo "2. Confirm Warcraft III Reforged runs once." >&2
      echo "3. Download the Windows launcher from https://w3champions.com/" >&2
      echo "4. Install the MSI into this prefix (WebView2 required)." >&2
      echo "Then: bnet-w3c" >&2
      exit 1
    fi
    exec ${bnetRun}/bin/bnet-run "$exe" "$@"
  '';

  bnetSetup = pkgs.writeShellScriptBin "bnet-setup" ''
    set -euo pipefail
    prefix="''${BNET_PREFIX:-$HOME/Games/battlenet}"
    mkdir -p "$prefix"
    cat > "$prefix/NIX-BNET.txt" <<EOF
    This Wine/Proton prefix is owned by modules.gaming.bnet (dotfiles).
    Launch with: bnet | bnet-wc3 | bnet-wow | bnet-w3c
    Do not wineboot this prefix with system wine.
    First-time Battle.net install may still use Lutris; afterwards use bnet.
    Prefix: $prefix
    EOF
    echo "prefix: $prefix"
    if [ -f "$prefix/drive_c/Program Files (x86)/Battle.net/Battle.net.exe" ]; then
      echo "Battle.net: installed"
    else
      echo "Battle.net: missing — install via Lutris (Battle.net) or the Battle.net-Setup.exe into this prefix"
    fi
    if [ -f "$prefix/drive_c/Program Files (x86)/Warcraft III/_retail_/x86_64/Warcraft III.exe" ]; then
      echo "Warcraft III: installed"
    else
      echo "Warcraft III: missing"
    fi
    echo "Launch: bnet"
  '';

  hyprRules = ''
    # Generated by modules.gaming.bnet. umu/Proton class is steam_app_default.
    ${optionalString (cfg.primaryOutput != null) ''
    exec-once = xrandr --output ${cfg.primaryOutput} --primary
    ''}
    # Launcher is a resizable CEF window (no min=max size hints). Tile it.
    # forcergbx stays: CEF's alpha buffer goes black without it.
    windowrulev2 = tile, class:^(steam_app_default)$, title:^(Battle\.net)
    windowrulev2 = forcergbx, class:^(steam_app_default)$, title:^(Battle\.net)
    windowrulev2 = forcergbx, class:^(battle\.net\.exe)$
    # explorer.exe /desktop: Proton's shell, empty title, size locked at 160x20.
    # Hyprland floats that in the corner. It is not a UI; do not close the process.
    windowrulev2 = workspace special:wine silent, class:^(steam_app_default)$, title:^$
    windowrulev2 = nofocus, class:^(steam_app_default)$, title:^$
    windowrulev2 = noborder, class:^(steam_app_default)$, title:^$
    windowrulev2 = noshadow, class:^(steam_app_default)$, title:^$
    windowrulev2 = float, class:^(steam_app_default)$, title:^(Warcraft III)
    windowrulev2 = center, class:^(steam_app_default)$, title:^(Warcraft III)
    windowrulev2 = monitor DP-3, class:^(steam_app_default)$, title:^(Warcraft III)
    windowrulev2 = noborder, class:^(steam_app_default)$, title:^(Warcraft III)
    windowrulev2 = rounding 0, class:^(steam_app_default)$, title:^(Warcraft III)
    windowrulev2 = noshadow, class:^(steam_app_default)$, title:^(Warcraft III)
    windowrulev2 = opaque, class:^(steam_app_default)$, title:^(Warcraft III)
  '';
in {
  options.modules.gaming.bnet = {
    enable = mkEnableOption "Battle.net prefix (WoW, Warcraft III, W3Champions, WowUp)";

    nvidia = mkOption {
      type = types.bool;
      default = true;
      description = "Pin Vulkan/DXVK to the NVIDIA ICD (hides llvmpipe/nouveau from Wine).";
    };

    primaryOutput = mkOption {
      type = types.nullOr types.str;
      default = "DP-3";
      description = "xrandr output Wine should treat as primary (kiss BenQ). Null to skip.";
    };

    extraEnv = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = "Extra environment for every bnet-run launch (W3C, DXVK knobs, …).";
    };

    wowup = mkOption {
      type = types.bool;
      default = true;
      description = "Install wowup-cf (addon manager). Forever needs WowUp 2.24+.";
    };

    w3champions = mkOption {
      type = types.bool;
      default = true;
      description = "Install the bnet-w3c launcher stub (installs nothing until the MSI is in the prefix).";
    };
  };

  config = mkIf cfg.enable {
    modules.gaming.steam.enable = true;

    environment.systemPackages = [
      bnetRun
      bnet
      bnetWc3
      bnetWow
      bnetSetup
      pkgs.winetricks
    ] ++ optional cfg.wowup pkgs.wowup-cf
      ++ optional cfg.w3champions bnetW3c;

    home-manager.users.nicho = {
      xdg.configFile."hypr-host/bnet.conf".text = hyprRules;

      xdg.desktopEntries = {
        bnet = {
          name = "Battle.net";
          comment = "Blizzard Battle.net (umu / Proton, Nix-owned prefix)";
          exec = "bnet";
          icon = "applications-games";
          terminal = false;
          categories = [ "Game" ];
        };
        bnet-wc3 = {
          name = "Warcraft III Reforged";
          comment = "Warcraft III from the Battle.net prefix";
          exec = "bnet-wc3";
          icon = "applications-games";
          terminal = false;
          categories = [ "Game" ];
        };
        bnet-wow = {
          name = "World of Warcraft";
          comment = "Retail / Forever from the Battle.net prefix";
          exec = "bnet-wow";
          icon = "applications-games";
          terminal = false;
          categories = [ "Game" ];
        };
      } // optionalAttrs cfg.w3champions {
        bnet-w3c = {
          name = "W3Champions";
          comment = "Community WC3 ladder (install MSI into the Battle.net prefix first)";
          exec = "bnet-w3c";
          icon = "applications-games";
          terminal = false;
          categories = [ "Game" ];
        };
      };
    };
  };
}

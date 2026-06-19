# Even Realities G2 — Hub app development toolchain on ene (no Claude Code).
#
# Provides evenhub-cli + evenhub-simulator for hermes user, workspace layout,
# and tailnet-only firewall rules for dev servers + simulator automation.
#
# After switch:
#   sudo -u hermes even-g2-update
#   cd ~/.hermes/workspace/mcp/even && ./install.sh && ./rebuild-index.sh
#   ./sync-even-skills.sh
#
{ config, pkgs, lib, ... }:

let
  cfg = config.modules.servers.even-g2;
  nodePkg = pkgs.nodejs_24;

  simRuntimeLibs = with pkgs; [
    gtk3 webkitgtk_4_1 gdk-pixbuf cairo glib libsoup_3 alsa-lib
    pango harfbuzz freetype fontconfig libepoxy at-spi2-atk libxkbcommon
    xorg.libX11 xorg.libXext xorg.libXrender xorg.libXi xorg.libXcursor
    xorg.libXrandr xorg.libXfixes xorg.libxcb patchelf
    mesa libglvnd dbus at-spi2-core
  ];

  simLdPath = lib.makeLibraryPath simRuntimeLibs;

  evenBin = "/var/lib/hermes/.hermes/workspace/even/bin";

  npmGlobals = [
    "@evenrealities/evenhub-cli@latest"
    "@evenrealities/evenhub-simulator@latest"
  ];

  provisionScript = pkgs.writeShellScriptBin "even-g2-update" ''
    set -euo pipefail
    export HOME="''${EVEN_G2_HOME:-/var/lib/hermes}"
    export USER="''${EVEN_G2_USER:-hermes}"
    export npm_config_prefix="$HOME/.npm-global"
    mkdir -p "$npm_config_prefix/bin"

    echo "[even-g2] Installing Even Hub npm globals into $npm_config_prefix ..."
    for pkg in ${lib.concatStringsSep " " (map (p: "\"${p}\"") npmGlobals)}; do
      echo "[even-g2]  → $pkg"
      ${nodePkg}/bin/npm install -g "$pkg" 2>&1 | tail -3 || true
    done

    if ! grep -q ".npm-global/bin" "$HOME/.profile" 2>/dev/null; then
      echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> "$HOME/.profile"
    fi

    # Patch native simulator binary for NixOS (same pattern as agent-browser).
    INTERPRETER="${pkgs.glibc}/lib/ld-linux-x86-64.so.2"
    SIM_BIN="$HOME/.npm-global/lib/node_modules/@evenrealities/evenhub-simulator/node_modules/@evenrealities/sim-linux-x64/bin/evenhub-simulator"
    if [ -f "$SIM_BIN" ]; then
      current=$(${pkgs.patchelf}/bin/patchelf --print-interpreter "$SIM_BIN" 2>/dev/null || true)
      if [ "$current" != "$INTERPRETER" ]; then
        ${pkgs.patchelf}/bin/patchelf --set-interpreter "$INTERPRETER" "$SIM_BIN" 2>/dev/null || true
      fi
    fi
    mkdir -p "$HOME"
    echo "${simLdPath}" > "$HOME/.even-sim-ldpath"

    echo "[even-g2] Done."
    for bin in evenhub evenhub-simulator; do
      if command -v "$bin" >/dev/null 2>&1; then
        echo "  ✓ $bin"
      else
        echo "  ✗ $bin (missing — re-run even-g2-update)"
      fi
    done
  '';

in
{
  options.modules.servers.even-g2 = {
    enable = lib.mkEnableOption "Even Realities G2 Hub development toolchain";

    workspace = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/hermes/.hermes/workspace/even";
      description = "Root for G2 app projects.";
    };

    devServerPorts = lib.mkOption {
      type = lib.types.listOf lib.types.int;
      default = [ 5173 5174 5175 3000 3001 9898 ];
      description = "Dev + simulator automation ports allowed on tailscale0 only.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      nodePkg
      provisionScript
      xvfb-run
      tailscale
    ] ++ simRuntimeLibs;

    users.users.hermes.packages = with pkgs; [
      nodePkg
      provisionScript
      xvfb-run
      tailscale
    ] ++ simRuntimeLibs;

    # even/bin helper scripts (even-dev.sh, even-sim.sh, even-smoke.sh, …)
    environment.sessionVariables.EVEN_BIN = evenBin;
    environment.sessionVariables.PATH = lib.mkAfter [ "${evenBin}" ];

    system.activationScripts.even-g2-provision = lib.stringAfter [ "users" "groups" "hermes-workspace" ] ''
      mkdir -p "${cfg.workspace}/apps"
      chown hermes:hermes "${cfg.workspace}" "${cfg.workspace}/apps" 2>/dev/null || true
      chmod 2775 "${cfg.workspace}" "${cfg.workspace}/apps" 2>/dev/null || true
      EVEN_G2_HOME=/var/lib/hermes EVEN_G2_USER=hermes ${provisionScript}/bin/even-g2-update || true
      chown -R hermes:hermes /var/lib/hermes/.npm-global 2>/dev/null || true
    '';

    networking.firewall.interfaces."tailscale0".allowedTCPPorts = lib.mkAfter cfg.devServerPorts;
  };
}
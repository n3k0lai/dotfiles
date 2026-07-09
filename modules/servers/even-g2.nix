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

  hermesHome = "/var/lib/hermes";
  hermesSoul = "${hermesHome}/.hermes";
  hermesWorkspace = "${hermesSoul}/workspace";
  eneDir = "${cfg.workspace}/even-terminal-ene";

  evenTerminalStart = pkgs.writeShellScriptBin "even-terminal-ene" ''
    set -euo pipefail
    export HOME="${hermesHome}"
    export PATH="${hermesHome}/.grok/bin:''${HOME}/.npm-global/bin:''${PATH:-/bin}"
    exec ${nodePkg}/bin/node "${eneDir}/src/cli.js" "$@"
  '';

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

    # even-terminal-ene: Grok (claude wire) + Hermes (codex wire) glasses bridge
    ENE_DIR="${cfg.workspace}/even-terminal-ene"
    if [ -f "$ENE_DIR/package.json" ]; then
      echo "[even-g2] Installing even-terminal-ene deps …"
      ${nodePkg}/bin/npm install --prefix "$ENE_DIR" 2>&1 | tail -3 || true
    fi

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
      default = [ 3456 5173 5174 5175 3000 3001 9898 ];
      description = "Even Terminal bridge (3456) + dev + simulator automation ports on tailscale0 only.";
    };

    terminalService = {
      enable = lib.mkEnableOption "even-terminal-ene systemd service (G2 Terminal Mode bridge)";

      port = lib.mkOption {
        type = lib.types.port;
        default = 3456;
        description = "HTTP port for the Even app (tailscale0 only via firewall).";
      };

      token = lib.mkOption {
        type = lib.types.str;
        default = "ene-g2-bridge";
        description = "Auth token the Even app sends as ?token= or Bearer.";
      };

      cwd = lib.mkOption {
        type = lib.types.str;
        default = hermesSoul;
        description = "Default cwd for Grok/Hermes sessions (soul repo — matches Cursor/Grok Build).";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    modules.servers.even-g2.terminalService.enable = lib.mkDefault true;

    environment.systemPackages = with pkgs; [
      nodePkg
      provisionScript
      evenTerminalStart
      xvfb-run
      tailscale
    ] ++ simRuntimeLibs;

    users.users.hermes.packages = with pkgs; [
      nodePkg
      provisionScript
      evenTerminalStart
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

    systemd.services.even-terminal-ene = lib.mkIf cfg.terminalService.enable {
      description = "Even G2 Terminal bridge (Grok Build + Hermes Agent)";
      documentation = [ "https://www.npmjs.com/package/@evenrealities/even-terminal" ];
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "hermes-agent-grok-provision.service"
      ];
      wants = [ "network-online.target" ];

      environment = {
        HOME = hermesHome;
        HERMES_HOME = "${hermesHome}/.hermes";
        EVEN_TERMINAL_CWD = cfg.terminalService.cwd;
        BRIDGE_TOKEN = cfg.terminalService.token;
        PORT = toString cfg.terminalService.port;
        GROK_BIN = "${hermesHome}/.grok/bin/grok";
      };

      serviceConfig = {
        User = "hermes";
        Group = "users";
        WorkingDirectory = cfg.terminalService.cwd;
        ExecStart = "${evenTerminalStart}/bin/even-terminal-ene --port ${toString cfg.terminalService.port} --token ${cfg.terminalService.token} --cwd ${cfg.terminalService.cwd} --tailscale --no-qr";
        # Ensure grok children die with the bridge (prevents orphan hung agents).
        KillMode = "control-group";
        KillSignal = "SIGTERM";
        TimeoutStopSec = 30;
        Restart = "always";
        RestartSec = 5;
        UMask = "0007";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = false;
        ReadWritePaths = [
          hermesHome
          cfg.terminalService.cwd
          cfg.workspace
        ];
        PrivateTmp = true;
      };

      path = [
        nodePkg
        pkgs.bash
        pkgs.coreutils
        pkgs.tailscale
        pkgs.sqlite
      ] ++ lib.optionals (config.services.hermes-agent.enable or false) [
        config.services.hermes-agent.package
      ];
    };
  };
}
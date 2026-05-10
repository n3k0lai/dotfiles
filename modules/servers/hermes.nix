# Hermes Agent — Nous Research autonomous agent
{ config, pkgs, lib, ... }:

let
  nodePkg = pkgs.nodejs_22;
  cfg = config.modules.servers.hermes;
  agentBrowserFix = pkgs.writeShellScriptBin "hermes-browser-fix" ''
    set -e
    INTERPRETER="${pkgs.glibc}/lib/ld-linux-x86-64.so.2"

    # Patch any agent-browser binaries found in hermes npx cache
    if [ -d /var/lib/hermes/.npm/_npx ]; then
      find /var/lib/hermes/.npm/_npx -name "agent-browser-linux-x64" -type f 2>/dev/null | while read -r binary; do
        current_interp=$(${pkgs.patchelf}/bin/patchelf --print-interpreter "$binary" 2>/dev/null || true)
        if [ "$current_interp" != "$INTERPRETER" ]; then
          ${pkgs.patchelf}/bin/patchelf --set-interpreter "$INTERPRETER" "$binary"
          echo "Patched: $binary"
        fi
      done
    fi

    # Ensure agent-browser config points to NixOS chromium
    mkdir -p /var/lib/hermes/.agent-browser
    ${pkgs.jq}/bin/jq -n \
      --arg chromium "${pkgs.chromium}/bin/chromium" \
      '{executablePath: $chromium}' \
      > /var/lib/hermes/.agent-browser/config.json

    # Fix ownership
    chown -R hermes:users /var/lib/hermes/.agent-browser 2>/dev/null || true
  '';
in
{
  options.modules.servers.hermes = {
    enable = lib.mkEnableOption "Hermes Agent";
    envFile = lib.mkOption {
      type = lib.types.path;
      default = ./secrets/hermes_env.age;
      description = "Path to the agenix-encrypted env file for Hermes";
    };
  };

  config = lib.mkIf cfg.enable {
    # Secrets (decrypted at activation by agenix)
    age.secrets.hermes-env = {
      file = cfg.envFile;
      owner = "nicho";
      group = "users";
      mode = "0400";
    };

  environment.systemPackages = with pkgs; [
    nodePkg
    gh
  ];

  # Run fix on every activation (nixos-rebuild switch)
  system.activationScripts.hermes-browser-fix = lib.stringAfter [ "users" "groups" ] ''
    ${agentBrowserFix}/bin/hermes-browser-fix
  '';

  # Also run fix automatically when hermes-agent starts/restarts
  systemd.services.hermes-agent-browser-fix = {
    description = "Patch Hermes agent-browser binary for NixOS";
    after = [ "hermes-agent.service" ];
    wants = [ "hermes-agent.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${agentBrowserFix}/bin/hermes-browser-fix";
      User = "root";
    };
  };

  # Hermes user-specific packages (browser automation)
  users.users.hermes.packages = with pkgs; [
    # Browser automation dependencies
    chromium
    patchelf
    jq
    # Required for headless browser operation
    nss
    nspr
    alsa-lib
    cups
    libdrm
    mesa
    xorg.libXcomposite
    xorg.libXdamage
    xorg.libXrandr
    xorg.libXScrnSaver
    xorg.libxshmfence
    libxkbcommon
    pango
    cairo
    gdk-pixbuf
    glib
    gtk3
    at-spi2-atk
    at-spi2-core
    dbus
    expat
    xorg.libxcb
    xorg.libX11
    xorg.libXext
    xorg.libXfixes
    xorg.libXrender
    xorg.libXcursor
    xorg.libXi
    xorg.libXinerama
    xorg.libXtst
    xorg.libxkbfile
    fontconfig
    freetype
    lcms
    libpng
    libjpeg
    libwebp
    libxml2
    libxslt
    sqlite
  ];

  # Hermes Agent — Nous Research autonomous agent
  services.hermes-agent = {
    enable = true;
    settings = {
      model = {
        # Primary: Nous Portal (Kimi K2.6)
        base_url = "https://api.nousresearch.com/v1";
        default = "moonshotai/kimi-k2.6";
        provider = "nous";
        # Fallback to OpenRouter configured via env vars
      };
      toolsets = [ "all" ];
      max_turns = 100;
      memory = { memory_enabled = true; user_profile_enabled = true; };
      browser = {
        cloud_provider = "browser-use";
        use_gateway = true;
      };
      # OpenCode delegation with model-specific subagents
      delegation = {
        enabled = true;
        agents = {
          # Fast/cheap tasks (K2.5 via OpenRouter free tier)
          "opencode-fast" = {
            command = "opencode";
            workdir = "/var/lib/hermes/workspace";
            args = [ "-m" "openrouter/nousresearch/hermes-3-llama-3.1-405b:free" ];
          };
          # Reasoning tasks (Hermes 4)
          "opencode-reasoning" = {
            command = "opencode";
            workdir = "/var/lib/hermes/workspace";
            args = [ "-m" "openrouter/nousresearch/hermes-4-405b" ];
          };
          # Coding tasks (Codestral)
          "opencode-code" = {
            command = "opencode";
            workdir = "/var/lib/hermes/workspace";
            args = [ "-m" "openrouter/mistralai/codestral-2508" ];
          };
          # General purpose (K2.6 via OpenRouter)
          opencode = {
            command = "opencode";
            workdir = "/var/lib/hermes/workspace";
            args = [ "-m" "openrouter/moonshotai/kimi-k2.6" ];
          };
        };
      };
    };
    environmentFiles = [ config.age.secrets.hermes-env.path ];
    addToSystemPackages = true;
    # Browser automation support
    extraPackages = with pkgs; [
      chromium
      patchelf
      git
    ];
  };

  # Environment for browser tools to find Chromium
  environment.variables = {
    PUPPETEER_EXECUTABLE_PATH = "${pkgs.chromium}/bin/chromium";
    PLAYWRIGHT_BROWSERS_PATH = "${pkgs.chromium}";
    CHROME_BIN = "${pkgs.chromium}/bin/chromium";
  };

  };
}

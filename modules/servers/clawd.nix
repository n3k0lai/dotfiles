# OpenClaw (Ene) - AI assistant + Grok fallback proxy + Hermes Agent
{ config, pkgs, lib, ... }:

let
  nodePkg = pkgs.nodejs_22;
  grokPython = pkgs.python3.withPackages (ps: [ ps.aiohttp ]);
in
{
  # Secrets (decrypted at activation by agenix)
  age.secrets.openclaw-env = {
    file = ./secrets/openclaw_env.age;
    owner = "nicho";
    group = "users";
    mode = "0400";
  };

  age.secrets.hermes-env = {
    file = ./secrets/hermes_env.age;
    owner = "nicho";
    group = "users";
    mode = "0400";
  };

  environment.systemPackages = with pkgs; [
    nodePkg
    gh
    # OpenCode CLI for agent delegation
    (pkgs.writeShellScriptBin "opencode" ''
      exec ${nodePkg}/bin/npx -y opencode@latest "$@"
    '')
    # Browser automation dependencies
    chromium
    patchelf
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

  systemd.services.openclaw-gateway = {
    description = "OpenClaw Gateway (Ene)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      HOME = "/home/nicho";
    };

    path = [ nodePkg ];

    serviceConfig = {
      User = "nicho";
      Group = "users";
      # Ensure port 18789 is free before starting (kills any orphaned process holding it)
      ExecStartPre = "${pkgs.bash}/bin/bash -c '${pkgs.util-linux}/bin/fuser -k -KILL 18789/tcp 2>/dev/null || true; sleep 2'";
      ExecStart = "${nodePkg}/bin/node /home/nicho/.npm-global/lib/node_modules/openclaw/dist/index.js gateway --port 18789";
      Restart = "always";
      RestartSec = 5;
      # Kill entire process group, not just main PID — prevents orphans
      KillMode = "control-group";
      EnvironmentFile = config.age.secrets.openclaw-env.path;
      Environment = [
        "PATH=/home/nicho/bin:/home/nicho/.npm-global/bin:${nodePkg}/bin:/run/current-system/sw/bin"
      ];
    };
  };

  # Hermes Agent — Nous Research autonomous agent
  services.hermes-agent = {
    enable = true;
    settings = {
      model = {
        base_url = "https://openrouter.ai/api/v1";
        default = "moonshotai/kimi-k2.5";
      };
      toolsets = [ "all" ];
      max_turns = 100;
      memory = { memory_enabled = true; user_profile_enabled = true; };
      # OpenCode delegation support
      delegation = {
        enabled = true;
        agents = {
          opencode = {
            command = "opencode";
            workdir = "/var/lib/hermes/workspace";
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

  # Cost-effective Grok fallback — Claude primary, Grok for bulk/cheap tasks
  systemd.services.grok-proxy = {
    description = "Grok API Proxy for OpenClaw";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      User = "nicho";
      Group = "users";
      ExecStart = "${grokPython}/bin/python3 /home/nicho/bin/grok-proxy.py";
      Restart = "always";
      RestartSec = 5;
      EnvironmentFile = "/home/nicho/.config/grok-proxy.env";
    };
  };
}

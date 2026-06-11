# Hermes Agent — Nous Research autonomous agent
{ config, pkgs, lib, hermes-agent ? null, ... }:

let
  nodePkg = pkgs.nodejs_24;
  cfg = config.modules.servers.hermes;

  agentBrowserFix = pkgs.writeShellScriptBin "hermes-browser-fix" ''
    set -e
    INTERPRETER="${pkgs.glibc}/lib/ld-linux-x86-64.so.2"

    # Patch any agent-browser binaries found in hermes npx / global npm caches.
    # Covers both npx temporary installs and `npm install -g` (which land in
    # .npm-global or .npm caches depending on prefix).
    for base in \
      /var/lib/hermes/.npm/_npx \
      /var/lib/hermes/.npm-global \
      /var/lib/hermes/.npm \
      /var/lib/hermes/.local; do
      if [ -d "$base" ]; then
        find "$base" -name "agent-browser-linux-x64" -type f 2>/dev/null | while read -r binary; do
          current_interp=$(${pkgs.patchelf}/bin/patchelf --print-interpreter "$binary" 2>/dev/null || true)
          if [ "$current_interp" != "$INTERPRETER" ]; then
            ${pkgs.patchelf}/bin/patchelf --set-interpreter "$INTERPRETER" "$binary"
            echo "Patched: $binary"
          fi
        done
      fi
    done

    # Ensure agent-browser config points to NixOS chromium
    mkdir -p /var/lib/hermes/.agent-browser
    ${pkgs.jq}/bin/jq -n \
      --arg chromium "${pkgs.chromium}/bin/chromium" \
      '{executablePath: $chromium}' \
      > /var/lib/hermes/.agent-browser/config.json

    # Fix ownership
    chown -R hermes:users /var/lib/hermes/.agent-browser 2>/dev/null || true
  '';

  # Provision the official x.ai Grok CLI (grok + agent) for the hermes user so that
  # delegation.agents.grok-build* (which shell out to "grok") can actually find it.
  # The CLI is installed to $HOME/.grok/bin (with HOME=/var/lib/hermes for the service user).
  # Auth is separate from Hermes' xai-oauth (it uses its own ~/.grok/auth.json); run
  # `sudo -u hermes HOME=/var/lib/hermes grok login` (or grok-update first) if needed.
  # We re-use the grok-update script from grokbuild when available.
  grokProvision = pkgs.writeShellScriptBin "hermes-grok-provision" ''
    set -e
    export HOME=/var/lib/hermes
    export USER=hermes

    GROK_BIN="$HOME/.grok/bin/grok"
    if [ ! -x "$GROK_BIN" ]; then
      echo "[hermes-grok-provision] Grok CLI not found for hermes user; installing..."
      if command -v grok-update >/dev/null 2>&1; then
        # grok-update respects GROK_CHANNEL and existing auth.json
        env HOME=$HOME USER=$USER grok-update || true
      else
        # Fallback to the official installer
        ${pkgs.curl}/bin/curl -fsSL https://x.ai/cli/install.sh | \
          SHELL=/bin/bash GROK_CHANNEL="''${GROK_CHANNEL:-stable}" bash || true
      fi
    fi

    # Ensure correct ownership (the install may have run as root in some flows)
    if [ -d "$HOME/.grok" ]; then
      chown -R hermes:hermes "$HOME/.grok" 2>/dev/null || true
    fi

    if [ -x "$GROK_BIN" ]; then
      echo "[hermes-grok-provision] Grok CLI ready at $GROK_BIN"
    else
      echo "[hermes-grok-provision] Warning: grok still not present after attempt. The grok-build delegation agents will fail until it is installed and logged in."
    fi
  '';

  # Ensure the agent-browser CLI is installed for the hermes user.
  # This is required even for cloud browser providers (browser-use, etc.) because
  # the browser tool surface and the Nous Tool Gateway status logic gate
  # "browser automation" selection/availability on the presence of the agent-browser
  # CLI (see _has_agent_browser and _resolve_browser_feature_state).
  # The existing hermes-browser-fix activation will then patch the linux-x64 binary
  # it finds (in .npm/_npx or global caches).
  agentBrowserProvision = pkgs.writeShellScriptBin "hermes-agent-browser-provision" ''
    set -e
    # Run the install as the hermes user so npm prefix and ownership are correct.
    ${pkgs.su}/bin/su -l hermes -c '
      export HOME=/var/lib/hermes
      export USER=hermes
      if ! command -v agent-browser >/dev/null 2>&1; then
        echo "[hermes-agent-browser-provision] agent-browser CLI not found for hermes user; installing via npm..."
        export npm_config_prefix="$HOME/.npm-global"
        mkdir -p "$npm_config_prefix"
        npm install -g agent-browser 2>&1 | tail -5 || true
      fi
      # Ensure bins owned.
      if [ -d "$HOME/.npm-global" ]; then
        chown -R hermes:hermes "$HOME/.npm-global" 2>/dev/null || true
      fi
      if [ -d "$HOME/.npm" ]; then
        chown -R hermes:hermes "$HOME/.npm" 2>/dev/null || true
      fi
      # Add to PATH for the user (for interactive hermes status etc.)
      if ! grep -q ".npm-global/bin" "$HOME/.profile" 2>/dev/null; then
        echo "export PATH=\"\$HOME/.npm-global/bin:\$PATH\"" >> "$HOME/.profile"
      fi
    ' || true
  '';

  # Static wrapper so which("agent-browser") succeeds for hermes user commands
  # (interactive hermes status, doctor, etc.) and for the gateway process.
  # It delegates to the user-installed location (populated by the provision).
  # Hermes dashboard validates Host (127.0.0.1 only). Tailscale Serve forwards the
  # MagicDNS hostname, so we rewrite Host on a localhost proxy before serve.
  serveProxyPort = 9120;
  serveProxyCaddyfile = pkgs.writeText "hermes-dashboard-serve-proxy.Caddyfile" ''
    {
      admin off
    }
    :${toString serveProxyPort} {
      bind 127.0.0.1
      reverse_proxy 127.0.0.1:9119 {
        header_up Host 127.0.0.1
      }
    }
  '';

  agentBrowserWrapper = pkgs.writeShellScriptBin "agent-browser" ''
    set -euo pipefail
    for cand in \
      "/var/lib/hermes/.npm-global/bin/agent-browser" \
      "/var/lib/hermes/.local/bin/agent-browser" \
      "/var/lib/hermes/.npm/_npx/$(ls /var/lib/hermes/.npm/_npx 2>/dev/null | head -1 2>/dev/null || echo 'dummy')/agent-browser" \
      "$(command -v agent-browser 2>/dev/null || true)"; do
      if [ -x "$cand" ]; then
        exec "$cand" "$@"
      fi
    done
    echo "agent-browser not found (the provision script should install it on activation)." >&2
    exit 127
  '';
in
{
  options.modules.servers.hermes = {
    enable = lib.mkEnableOption "Hermes Agent";
    user = lib.mkOption {
      type = lib.types.str;
      default = "hermes";
      description = "User to run the Hermes dashboard under";
    };
    group = lib.mkOption {
      type = lib.types.str;
      default = "users";
      description = "Group to run the Hermes dashboard under";
    };
    envFile = lib.mkOption {
      type = lib.types.path;
      default = ./secrets/hermes_env.age;
      description = "Path to the agenix-encrypted env file for Hermes";
    };
    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/hermes";
      description = "State directory for Hermes";
    };
    workingDirectory = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/hermes/.hermes/workspace";
      description = "Working directory for the Hermes gateway/dashboard itself";
    };
    delegationWorkdir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/hermes/.hermes/workspace";
      description = "Working directory passed to delegated external agents (e.g. grok-build sub-processes). Unified with workingDirectory under .hermes/workspace.";
    };
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Extra packages available to the Hermes service";
    };
    tailscaleServe = {
      enable = lib.mkEnableOption ''
        Expose the Hermes dashboard on the tailnet via Tailscale Serve (MagicDNS).
        Access at https://<hostname>.<tailnet>.ts.net — not on the public internet.
      '';
      target = lib.mkOption {
        type = lib.types.str;
        default = toString serveProxyPort;
        description = "Local port passed to tailscale serve (via Host-rewrite proxy, not dashboard directly).";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # nicho needs group membership to read the canonical dotfiles checkout for
    # nixos-rebuild switch (hermes edits without sudo; nicho activates).
    users.users.nicho.extraGroups = lib.mkAfter [ "hermes" ];

    # Dotfiles git repo is owned by hermes; nicho activates via nixos-rebuild.
    # Git refuses foreign-owned repos unless listed in safe.directory (both paths:
    # canonical checkout and ~/dotfiles symlink target).
    # configuration-server.nix does not enable programs.git — turn it on here.
    programs.git = {
      enable = true;
      config.safe.directory = [
        "${cfg.delegationWorkdir}/dotfiles"
        "${cfg.stateDir}/dotfiles"
      ];
    };

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

  # Ensure agent-browser CLI is present (required for browser tool surface and for
  # the "Browser automation" category to be marked selected in the Nous Tool Gateway
  # status, even when using cloud_provider=browser-use + gateway).
  system.activationScripts.hermes-agent-browser-provision = lib.stringAfter [ "users" "groups" "hermes-browser-fix" ] ''
    ${agentBrowserProvision}/bin/hermes-agent-browser-provision
  '';

  # Also ensure it after service (re)start.
  systemd.services.hermes-agent-browser-provision = {
    description = "Install agent-browser CLI for hermes user (for cloud/local browser providers and gateway selection)";
    after = [ "hermes-agent.service" ];
    wants = [ "hermes-agent.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${agentBrowserProvision}/bin/hermes-agent-browser-provision";
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
    # The wrapper makes `agent-browser` appear in the hermes user's profile PATH
    # so that `hermes status` / doctor etc. (run as hermes) see the CLI for the
    # browser feature state check.
    agentBrowserWrapper
  ];

  # Hermes Agent — Nous Research autonomous agent
  services.hermes-agent = {
    enable = true;
    # Force Node 24 (instead of hermes-agent's internal nodejs_22 pin) so that
    # npm install for ui-tui + web succeeds. The monorepo lockfile pulls in
    # @icons-pack/react-simple-icons@13.13.0 (via @nous-research/ui) which
    # declares engines: { node: ">=24", pnpm: ">=10" }.
    package = lib.mkForce (
      if hermes-agent != null then
        hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
          nodejs_22 = pkgs.nodejs_24;
        }
      else
        throw "hermes-agent input must be passed as specialArg (see flake.nix) to allow nodejs override for builds"
    );
    settings = {
      model = {
        # SuperGrok (xAI OAuth) — high-tier subscription (tier 5 / heavy).
        # This gives the agent direct access to the strongest Grok models + higher
        # limits via the stored xai-oauth credential (see hermes auth / auth.json).
        # x_search (X/Twitter) and other xAI direct tools auto-prefer this path.
        provider = "xai-oauth";
        default = "grok-4.3";
      };
      toolsets = [ "all" ];
      max_turns = 100;
      memory = { memory_enabled = true; user_profile_enabled = true; };
      # Bias the main agent (and many sub-flows) toward deeper reasoning by default.
      # The supergrok subscription supports the higher effort levels well.
      # Valid: none|minimal|low|medium|high|xhigh. Individual delegation agents
      # below pass their own --effort to the external grok CLI.
      agent = {
        reasoning_effort = "high";
      };
      # Tool Gateway (Nous subscriber passthrough) for web + browser cloud tools.
      # These must be explicitly selected via backend/cloud_provider so that
      # `hermes tools` / status / agent see "Web" and "Browser automation" as
      # selected (use_gateway alone is not enough for the selection status).
      web = {
        backend = "firecrawl";
        use_gateway = true;
      };
      browser = {
        cloud_provider = "browser-use";
        use_gateway = true;
      };
      # Explicitly opt the browser category into the managed Nous Tool Gateway.
      # This is what makes "Browser automation" appear as "selected" in the
      # Nous Tool Gateway status (separate from cloud_provider + use_gateway
      # which control the actual routing). Web used the `backend` key for the
      # same purpose.
      tool_gateway = {
        browser = "gateway";
      };
      # Grok Build delegation (preferred for implementation-heavy work).
      # These spawn the official x.ai "grok" CLI (the same one you get from grok-update)
      # as a sub-agent. The CLI uses its own auth (~/.grok/auth.json) — ideally the
      # same supergrok account so the delegated work also benefits from the heavy tier.
      # The wrapper we inject into the hermes-agent unit PATH (below) makes "grok"
      # resolvable even though the real binary lives in the hermes user's home.
      delegation = {
        enabled = true;
        agents = {
          # Default general-purpose Grok Build agent
          grok-build = {
            command = "grok";
            workdir = cfg.delegationWorkdir;
          };

          # Quick iteration / low effort
          "grok-build-quick" = {
            command = "grok";
            workdir = cfg.delegationWorkdir;
            args = [ "--effort" "1" ];
          };

          # Balanced implementation with review (recommended)
          "grok-build-implement" = {
            command = "grok";
            workdir = cfg.delegationWorkdir;
            args = [ "--effort" "3" ];
          };

          # High rigor implementation (complex or sensitive work)
          "grok-build-thorough" = {
            command = "grok";
            workdir = cfg.delegationWorkdir;
            args = [ "--effort" "5" ];
          };

          # Specialized code-focused agent
          "grok-build-code" = {
            command = "grok";
            workdir = cfg.delegationWorkdir;
            args = [ "--agent" "code" "--effort" "3" ];
          };

          # Research / exploration focused
          "grok-build-research" = {
            command = "grok";
            workdir = cfg.delegationWorkdir;
            args = [ "--agent" "research" ];
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
      python312
      tesseract5
    ];
    mcpServers.nous = {
      command = "${cfg.delegationWorkdir}/mcp/nous/.venv/bin/python";
      args = [ "${cfg.delegationWorkdir}/mcp/nous/server.py" ];
      env = {
        NOUS_DOCS_DB = "${cfg.delegationWorkdir}/mcp/nous/data/docs.db";
        NOUS_DOCS_ROOT = "${cfg.delegationWorkdir}/mcp/nous/docs-source/website/docs";
      };
      tools = {
        include = [ "search_docs" "get_doc_page" "list_doc_sections" ];
      };
      timeout = 60;
    };
    mcpServers.guns = {
      command = "${cfg.delegationWorkdir}/mcp/guns/.venv/bin/python";
      args = [ "${cfg.delegationWorkdir}/mcp/guns/server.py" ];
      env = {
        HERMES_GUNS_DB = "${cfg.delegationWorkdir}/mcp/guns/data/manuals.db";
        HERMES_GUNS_VAULT = "/var/lib/hermes/vault/🚀projects/artemis";
        HERMES_TESSERACT_CMD = "${pkgs.tesseract5}/bin/tesseract";
      };
      tools = {
        include = [
          "list_guns"
          "get_gun_context"
          "search_manual"
          "get_manual_page"
          "list_manual_pages"
        ];
      };
      timeout = 90;
    };
    # Dependency groups for optional backends that are lazily imported at runtime.
    # The hermes-agent package uses a sealed venv; missing groups cause lazy_deps.py
    # "search.firecrawl" (and similar) to attempt `pip install` which fails on Nix,
    # surfacing as "web tools are not configured" + unhelpful update advice even when
    # the managed Tool Gateway (Nous) auth + use_gateway are ready.
    extraDependencyGroups = [
      "mcp"
      "messaging"
      "edge-tts"
      "firecrawl" # web_search + web_extract via Tool Gateway (or direct)
      # Add "fal" for image/video generation gateway, "exa"/"parallel-web" for other search
      # backends, "modal"/"daytona" for sandboxed code execution delegation, etc. as needed.
    ];
  };

  # Ensure the (unified) workspace exists and is owned by the hermes user.
  # Both the gateway/dashboard (workingDirectory) and delegated grok-build agents
  # (delegationWorkdir) now use .hermes/workspace to avoid drift.
  # Also symlink ${cfg.stateDir}/workspace -> .hermes/workspace so ~/workspace
  # (when HOME=${cfg.stateDir}) resolves to the canonical tree, not a ghost copy.
  system.activationScripts.hermes-workspace = lib.stringAfter [ "users" "groups" ] ''
    mkdir -p "${cfg.delegationWorkdir}"
    chown hermes:hermes "${cfg.delegationWorkdir}" 2>/dev/null || true
    chmod 2770 "${cfg.delegationWorkdir}" 2>/dev/null || true

    # Group traverse only: nicho (in hermes group) can reach workspace/dotfiles
    # without listing other contents under .hermes (secrets, agent state, etc.).
    HERMES_DIR="${cfg.stateDir}/.hermes"
    if [ -d "$HERMES_DIR" ]; then
      chown hermes:hermes "$HERMES_DIR" 2>/dev/null || true
      chmod 2710 "$HERMES_DIR" 2>/dev/null || true
    fi

    GHOST_WS="${cfg.stateDir}/workspace"
    CANON_WS="${cfg.delegationWorkdir}"
    if [ -e "$GHOST_WS" ] && [ ! -L "$GHOST_WS" ]; then
      rm -rf "$GHOST_WS"
    fi
    if [ ! -e "$GHOST_WS" ]; then
      ln -s "$CANON_WS" "$GHOST_WS"
      chown -h hermes:hermes "$GHOST_WS" 2>/dev/null || true
    elif [ -L "$GHOST_WS" ]; then
      CURRENT_TARGET=$(readlink "$GHOST_WS" || true)
      if [ "$CURRENT_TARGET" != "$CANON_WS" ]; then
        rm -f "$GHOST_WS"
        ln -s "$CANON_WS" "$GHOST_WS"
        chown -h hermes:hermes "$GHOST_WS" 2>/dev/null || true
      fi
    fi

    # Dotfiles live inside the workspace tree; keep ~/dotfiles as a stable alias
    # for fish helpers (ene.fish) and nixos-rebuild --flake ~/dotfiles#ene.
    DOTFILES_CANON="${cfg.delegationWorkdir}/dotfiles"
    DOTFILES_LINK="${cfg.stateDir}/dotfiles"
    mkdir -p "$DOTFILES_CANON"
    chown hermes:hermes "$DOTFILES_CANON" 2>/dev/null || true
    chmod 2770 "$DOTFILES_CANON" 2>/dev/null || true
    if [ -d "$DOTFILES_CANON/.git" ]; then
      su -s /bin/sh hermes -c "git -C '$DOTFILES_CANON' config core.sharedRepository group" 2>/dev/null || true
    fi
    if [ -e "$DOTFILES_LINK" ] && [ ! -L "$DOTFILES_LINK" ]; then
      if [ -d "$DOTFILES_LINK/.git" ] && [ ! -d "$DOTFILES_CANON/.git" ]; then
        rm -rf "$DOTFILES_CANON"
        mv "$DOTFILES_LINK" "$DOTFILES_CANON"
      else
        echo "hermes-workspace: refusing to replace non-symlink $DOTFILES_LINK" >&2
      fi
    fi
    if [ ! -e "$DOTFILES_LINK" ]; then
      ln -s "$DOTFILES_CANON" "$DOTFILES_LINK"
      chown -h hermes:hermes "$DOTFILES_LINK" 2>/dev/null || true
    elif [ -L "$DOTFILES_LINK" ]; then
      CURRENT_DF=$(readlink "$DOTFILES_LINK" || true)
      if [ "$CURRENT_DF" != "$DOTFILES_CANON" ]; then
        rm -f "$DOTFILES_LINK"
        ln -s "$DOTFILES_CANON" "$DOTFILES_LINK"
        chown -h hermes:hermes "$DOTFILES_LINK" 2>/dev/null || true
      fi
    fi
  '';

  # Provision local Hermes Agent docs MCP (workspace/mcp/nous): venv + index on first boot.
  system.activationScripts.hermes-nous-mcp = lib.stringAfter [ "users" "groups" "hermes-workspace" ] ''
    NOUS_DIR="${cfg.delegationWorkdir}/mcp/nous"
    if [ -f "$NOUS_DIR/install.sh" ]; then
      chmod +x "$NOUS_DIR/install.sh" "$NOUS_DIR/update-docs.sh" 2>/dev/null || true
      if [ ! -d "$NOUS_DIR/.venv" ] || [ ! -f "$NOUS_DIR/data/docs.db" ]; then
        su -s /bin/sh hermes -c "cd '$NOUS_DIR' && ./install.sh" 2>&1 | tail -20 || \
          echo "hermes-nous-mcp: install failed — run workspace/mcp/nous/update-docs.sh as hermes" >&2
      fi
    fi
  '';

  # Provision Artemis gun manuals MCP (workspace/mcp/guns): venv + PDF index on first boot.
  system.activationScripts.hermes-guns-mcp = lib.stringAfter [ "users" "groups" "hermes-workspace" "hermes-nous-mcp" ] ''
    GUNS_DIR="${cfg.delegationWorkdir}/mcp/guns"
    if [ -f "$GUNS_DIR/install.sh" ]; then
      chmod +x "$GUNS_DIR/install.sh" "$GUNS_DIR/rebuild-manuals.sh" 2>/dev/null || true
      if [ ! -d "$GUNS_DIR/.venv" ] || [ ! -f "$GUNS_DIR/data/manuals.db" ]; then
        su -s /bin/sh hermes -c "cd '$GUNS_DIR' && ./install.sh" 2>&1 | tail -30 || \
          echo "hermes-guns-mcp: install failed — run workspace/mcp/guns/rebuild-manuals.sh as hermes" >&2
      fi
    fi
  '';

  # Run grok CLI provisioning on every activation (so delegated grok-build* agents work).
  system.activationScripts.hermes-grok-provision = lib.stringAfter [ "users" "groups" "hermes-workspace" "hermes-nous-mcp" "hermes-guns-mcp" ] ''
    ${grokProvision}/bin/hermes-grok-provision
  '';

  # Also run it automatically when the hermes gateway (agent) starts/restarts.
  systemd.services.hermes-agent-grok-provision = {
    description = "Ensure x.ai Grok CLI is installed for hermes user (for grok-build delegation)";
    after = [ "hermes-agent.service" ];
    wants = [ "hermes-agent.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${grokProvision}/bin/hermes-grok-provision";
      User = "root";
    };
  };

  # Make the external "grok" command (used by all the grok-build-* delegation agents)
  # resolvable inside the hermes-agent gateway process. The real binary lives in the
  # hermes user's home after grok-update / the provision script above.
  # This wrapper gives a clear error + hint if it is still missing.
  systemd.services.hermes-agent = {
    serviceConfig = {
      # Unify the parent gateway process cwd into .hermes/workspace as well
      # (delegation workdir controls the chdir for child grok processes).
      WorkingDirectory = lib.mkForce cfg.workingDirectory;
    };
    path = lib.mkAfter [
      (pkgs.writeShellScriptBin "grok" ''
        set -euo pipefail
        GROK_BIN="/var/lib/hermes/.grok/bin/grok"
        if [ -x "$GROK_BIN" ]; then
          exec "$GROK_BIN" "$@"
        fi
        echo "grok CLI not found at $GROK_BIN for the hermes service user." >&2
        echo "It is normally installed by the hermes-grok-provision activation / service." >&2
        echo "Try: sudo -u hermes HOME=/var/lib/hermes grok-update && sudo -u hermes HOME=/var/lib/hermes grok login" >&2
        exit 127
      '')
      agentBrowserWrapper
    ];
  };


  # Hermes dashboard — web UI for managing agent config, sessions, logs
  systemd.services.hermes-dashboard = {
    description = "Hermes Agent Dashboard";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" "hermes-agent.service" ];
    wants = [ "network-online.target" "hermes-agent.service" ];

    environment = {
      HOME = cfg.stateDir;
      HERMES_HOME = "${cfg.stateDir}/.hermes";
      HERMES_MANAGED = "true";
      MESSAGING_CWD = cfg.workingDirectory;
    };

    serviceConfig = {
      User = cfg.user;
      Group = cfg.group;
      WorkingDirectory = cfg.workingDirectory;
      ExecStart = "${config.services.hermes-agent.package}/bin/hermes dashboard --no-open --port 9119 --host 127.0.0.1";
      Restart = "always";
      RestartSec = 5;
      UMask = "0007";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = false;
      ReadWritePaths = [ cfg.stateDir cfg.workingDirectory ];
      PrivateTmp = true;
    };

    path = [
      config.services.hermes-agent.package
      pkgs.bash
      pkgs.coreutils
      pkgs.git
      grokProvision
      agentBrowserProvision
      agentBrowserWrapper
    ] ++ cfg.extraPackages;
  };

  # Rewrites Host to 127.0.0.1 so the dashboard accepts Tailscale Serve traffic.
  systemd.services.hermes-dashboard-serve-proxy = lib.mkIf cfg.tailscaleServe.enable {
    description = "Host rewrite proxy for Tailscale Serve → Hermes dashboard";
    after = [ "network-online.target" "hermes-dashboard.service" ];
    wants = [ "network-online.target" "hermes-dashboard.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.caddy}/bin/caddy run --config ${serveProxyCaddyfile}";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

  # Tailnet-only HTTPS for the dashboard (MagicDNS). Replaces public Caddy + basic auth.
  systemd.services.hermes-dashboard-tailscale-serve = lib.mkIf cfg.tailscaleServe.enable {
    description = "Tailscale Serve: Hermes dashboard (tailnet only)";
    after = [
      "network-online.target"
      "tailscaled.service"
      "hermes-dashboard.service"
      "hermes-dashboard-serve-proxy.service"
    ];
    wants = [
      "network-online.target"
      "hermes-dashboard.service"
      "hermes-dashboard-serve-proxy.service"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.tailscale}/bin/tailscale serve --bg --yes ${cfg.tailscaleServe.target}";
      ExecStop = "${pkgs.tailscale}/bin/tailscale serve reset";
    };
  };

  # Environment for browser tools to find Chromium
  environment.variables = {
    PUPPETEER_EXECUTABLE_PATH = "${pkgs.chromium}/bin/chromium";
    PLAYWRIGHT_BROWSERS_PATH = "${pkgs.chromium}";
    CHROME_BIN = "${pkgs.chromium}/bin/chromium";
  };

  };
}

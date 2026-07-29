# Hermes Agent — Nous Research autonomous agent
{ config, pkgs, lib, hermes-agent ? null, ... }:

let
  nodePkg = pkgs.nodejs_24;
  cfg = config.modules.servers.hermes;

  # Store-pinned interpreter for generic Linux agent-browser ELFs on NixOS.
  # Used by both bulk oneshot (hermes-browser-fix) and the always-on wrapper
  # (patch-before-exec) so mid-session npx drops work without a rebuild.
  agentBrowserInterpreter = "${pkgs.glibc}/lib/ld-linux-x86-64.so.2";
  # Soft pin: provision installs this when the global native is missing.
  # Bump when intentionally upgrading; wrapper still works with any drop.
  agentBrowserVersion = "0.33.1";

  agentBrowserFix = pkgs.writeShellScriptBin "hermes-browser-fix" ''
    set -e
    INTERPRETER="${agentBrowserInterpreter}"
    FIND="${pkgs.findutils}/bin/find"
    MKDIR="${pkgs.coreutils}/bin/mkdir"
    CHOWN="${pkgs.coreutils}/bin/chown"
    PATCHELF="${pkgs.patchelf}/bin/patchelf"

    # Patch every agent-browser native binary under the hermes home tree.
    # npm/npx refreshes can drop a new dynamically-linked binary at any time.
    # Use store-pinned paths — ExecStartPre has no usable PATH on NixOS.
    "$FIND" /var/lib/hermes \
      -path '/var/lib/hermes/.cache/*' -prune \
      -o -name "agent-browser-linux-x64" -type f -print 2>/dev/null | while read -r binary; do
      current_interp=$("$PATCHELF" --print-interpreter "$binary" 2>/dev/null || true)
      if [ "$current_interp" != "$INTERPRETER" ]; then
        "$PATCHELF" --set-interpreter "$INTERPRETER" "$binary"
        echo "Patched: $binary"
      fi
    done

    # Ensure agent-browser config points to NixOS chromium
    "$MKDIR" -p /var/lib/hermes/.agent-browser
    ${pkgs.jq}/bin/jq -n \
      --arg chromium "${pkgs.chromium}/bin/chromium" \
      '{executablePath: $chromium}' \
      > /var/lib/hermes/.agent-browser/config.json

    # Fix ownership (config is written as root when run from systemd)
    "$CHOWN" -R hermes:users /var/lib/hermes/.agent-browser 2>/dev/null || true
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

    # Hermes uses bash (no fish dotfiles). Login shells read .profile only — mirror npm-global.
    if ! grep -q ".grok/bin" "$HOME/.profile" 2>/dev/null; then
      echo 'export PATH="$HOME/.grok/bin:$PATH"' >> "$HOME/.profile"
    fi
  '';

  # Ensure a real npm-global agent-browser native exists for the hermes user.
  # Required even for cloud browser providers (browser-use, etc.): Hermes gates
  # "browser automation" on a runnable agent-browser CLI (_find_agent_browser).
  # Do NOT use `command -v agent-browser` — the Nix profile wrapper is always
  # present and would skip install even when the native ELF is missing.
  agentBrowserProvision = pkgs.writeShellScriptBin "hermes-agent-browser-provision" ''
    set -e
    ${pkgs.su}/bin/su -l hermes -c '
      export HOME=/var/lib/hermes
      export USER=hermes
      export npm_config_prefix="$HOME/.npm-global"
      mkdir -p "$npm_config_prefix"
      NATIVE="$HOME/.npm-global/lib/node_modules/agent-browser/bin/agent-browser-linux-x64"
      if [ ! -x "$NATIVE" ]; then
        echo "[hermes-agent-browser-provision] installing agent-browser@${agentBrowserVersion} into npm-global..."
        npm install -g "agent-browser@${agentBrowserVersion}" 2>&1 | tail -8 || true
      fi
      if [ -d "$HOME/.npm-global" ]; then
        chown -R hermes:hermes "$HOME/.npm-global" 2>/dev/null || true
      fi
      if [ -d "$HOME/.npm" ]; then
        chown -R hermes:hermes "$HOME/.npm" 2>/dev/null || true
      fi
      # Prefer profile wrapper over raw npm-global ELF on interactive PATH.
      # Put wrapper dir first if present; keep npm-global as fallback only.
      if ! grep -q ".npm-global/bin" "$HOME/.profile" 2>/dev/null; then
        echo "export PATH=\"\$HOME/.npm-global/bin:\$PATH\"" >> "$HOME/.profile"
      fi
    ' || true
  '';

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

  # Durable agent-browser entrypoint for Hermes + interactive hermes shells.
  # Critical: patch-before-exec so a fresh npx drop mid-session works without
  # waiting for the oneshot/activation.
  # Hermes resolves CLI via shutil.which("agent-browser") then agent_browser_runnable
  # (--version). If the wrapper is first on PATH and returns a working --version,
  # Hermes never falls through to bare `npx agent-browser` (which re-drops ELFs).
  agentBrowserWrapper = pkgs.writeShellScriptBin "agent-browser" ''
    set -euo pipefail
    INTERPRETER="${agentBrowserInterpreter}"
    PATCHELF="${pkgs.patchelf}/bin/patchelf"
    FIND="${pkgs.findutils}/bin/find"
    SORT="${pkgs.coreutils}/bin/sort"
    CUT="${pkgs.coreutils}/bin/cut"
    HEAD="${pkgs.coreutils}/bin/head"
    self=$(readlink -f "$0" 2>/dev/null || echo "$0")

    patch_if_needed() {
      local binary="$1"
      local current
      current=$("$PATCHELF" --print-interpreter "$binary" 2>/dev/null || true)
      if [ -n "$current" ] && [ "$current" != "$INTERPRETER" ]; then
        "$PATCHELF" --set-interpreter "$INTERPRETER" "$binary" 2>/dev/null || true
      fi
    }

    # Prefer newest mtime so a just-npx'd binary wins over a stale global.
    # GNU find -printf is fine (Nix findutils). Only search dirs that exist.
    search_dirs=()
    for d in /var/lib/hermes/.npm-global /var/lib/hermes/.npm/_npx /var/lib/hermes/.local; do
      [ -d "$d" ] && search_dirs+=("$d")
    done
    if [ "''${#search_dirs[@]}" -gt 0 ]; then
      while IFS= read -r native; do
        [ -n "$native" ] || continue
        [ -x "$native" ] || continue
        patch_if_needed "$native"
        exec "$native" "$@"
      done < <(
        "$FIND" "''${search_dirs[@]}" \
          \( -name 'agent-browser-linux-x64' -type f \) -printf '%T@\t%p\n' 2>/dev/null \
          | "$SORT" -nr | "$CUT" -f2- | "$HEAD" -20 || true
      )
    fi

    # Fall back to npm-global shim only if it is not this wrapper.
    for cand in \
      "/var/lib/hermes/.npm-global/bin/agent-browser" \
      "/var/lib/hermes/.local/bin/agent-browser"; do
      cand_resolved=$(readlink -f "$cand" 2>/dev/null || echo "$cand")
      if [ -x "$cand" ] && [ "$cand_resolved" != "$self" ]; then
        # If the cand is itself the native ELF, patch first.
        if "$PATCHELF" --print-interpreter "$cand_resolved" >/dev/null 2>&1; then
          patch_if_needed "$cand_resolved"
        fi
        exec "$cand" "$@"
      fi
    done
    echo "agent-browser not found — run hermes-agent-browser-provision and hermes-browser-fix." >&2
    exit 127
  '';

  grokWrapper = pkgs.writeShellScriptBin "grok" ''
    set -euo pipefail
    GROK_BIN="/var/lib/hermes/.grok/bin/grok"
    if [ -x "$GROK_BIN" ]; then
      exec "$GROK_BIN" "$@"
    fi
    echo "grok CLI not found at $GROK_BIN for the hermes service user." >&2
    echo "It is normally installed by the hermes-grok-provision activation / service." >&2
    echo "Try: sudo -u hermes HOME=/var/lib/hermes grok-update && sudo -u hermes HOME=/var/lib/hermes grok login" >&2
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

    age.secrets.hermes-ssh-config = {
      file = ./secrets/hermes_ssh_config.age;
      owner = cfg.user;
      group = "users";
      mode = "0600";
      path = "${cfg.stateDir}/.ssh/config";
    };

  environment.systemPackages = with pkgs; [
    nodePkg
    gh
  ];

  # kiss → ene file drops (rulebooks, cookies, etc.) via nicho@ene; hermes installs.
  system.activationScripts.hermes-inbox = lib.stringAfter [ "users" "groups" ] ''
    mkdir -p ${cfg.stateDir}/inbox ${cfg.stateDir}/.ssh
    chown ${cfg.user}:${cfg.user} ${cfg.stateDir}/inbox ${cfg.stateDir}/.ssh
    chmod 2775 ${cfg.stateDir}/inbox
    chmod 700 ${cfg.stateDir}/.ssh
  '';

  # Run fix on every activation (nixos-rebuild switch)
  system.activationScripts.hermes-browser-fix = lib.stringAfter [ "users" "groups" ] ''
    ${agentBrowserFix}/bin/hermes-browser-fix
  '';

  # Bulk patch before gateway start. PartOf stops this unit when hermes-agent
  # stops, so RemainAfterExit does not skip re-runs on agent restart (the old
  # failure mode: active since 2026-07-07 while new npx drops went unpatched).
  systemd.services.hermes-agent-browser-fix = {
    description = "Patch Hermes agent-browser binary for NixOS";
    before = [ "hermes-agent.service" ];
    wantedBy = [ "hermes-agent.service" "multi-user.target" ];
    requiredBy = [ "hermes-agent.service" ];
    unitConfig = {
      PartOf = "hermes-agent.service";
    };
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

  systemd.services.hermes-agent-browser-provision = {
    description = "Install agent-browser CLI for hermes user (for cloud/local browser providers and gateway selection)";
    before = [ "hermes-agent-browser-fix.service" "hermes-agent.service" ];
    wantedBy = [ "hermes-agent.service" "multi-user.target" ];
    requiredBy = [ "hermes-agent.service" ];
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
    # Same for grok — hermes has no fish dotfiles; login shells need a store wrapper.
    grokWrapper
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
    # Agent config (model, discord, delegation, MCP, profiles) lives in the soul
    # repo at ~/.hermes/config.yaml — not here. Empty settings = activation merge
    # is a no-op and soul config survives rebuilds.
    settings = { };
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

    # Artemis code lives in workspace/artemis; keep ~/artemis as a stable alias.
    ARTEMIS_CANON="${cfg.delegationWorkdir}/artemis"
    ARTEMIS_LINK="${cfg.stateDir}/artemis"
    mkdir -p "$ARTEMIS_CANON"
    chown hermes:hermes "$ARTEMIS_CANON" 2>/dev/null || true
    chmod 2770 "$ARTEMIS_CANON" 2>/dev/null || true
    if [ -e "$ARTEMIS_LINK" ] && [ ! -L "$ARTEMIS_LINK" ]; then
      if [ -d "$ARTEMIS_LINK/.git" ] && [ ! -d "$ARTEMIS_CANON/.git" ]; then
        rm -rf "$ARTEMIS_CANON"
        mv "$ARTEMIS_LINK" "$ARTEMIS_CANON"
      else
        echo "hermes-workspace: refusing to replace non-symlink $ARTEMIS_LINK" >&2
      fi
    fi
    if [ ! -e "$ARTEMIS_LINK" ]; then
      ln -s "$ARTEMIS_CANON" "$ARTEMIS_LINK"
      chown -h hermes:hermes "$ARTEMIS_LINK" 2>/dev/null || true
    elif [ -L "$ARTEMIS_LINK" ]; then
      CURRENT_ART=$(readlink "$ARTEMIS_LINK" || true)
      if [ "$CURRENT_ART" != "$ARTEMIS_CANON" ]; then
        rm -f "$ARTEMIS_LINK"
        ln -s "$ARTEMIS_CANON" "$ARTEMIS_LINK"
        chown -h hermes:hermes "$ARTEMIS_LINK" 2>/dev/null || true
      fi
    fi
  '';

  # MCP venv/index bootstrap is soul-owned (workspace/mcp/*/install.sh).
  # Do not encode pack/db topography in Nix — see skills/nixos-hermes-operations
  # and workspace/mcp/provision-all.sh (hermes user, on demand).

  # Run grok CLI provisioning on every activation (so delegated grok-build* agents work).
  system.activationScripts.hermes-grok-provision = lib.stringAfter [ "users" "groups" "hermes-workspace" ] ''
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

  # Soul repo owns agent config. Upstream hermes-agent Nix module sets managed mode
  # (HERMES_MANAGED + .managed marker) which blocks CLI/dashboard edits — lift it.
  system.activationScripts.hermes-dynamic-config = lib.stringAfter [ "hermes-agent-setup" ] ''
    rm -f ${cfg.stateDir}/.hermes/.managed
  '';

  # Make the external "grok" / "agent-browser" commands resolvable inside the
  # hermes-agent gateway process.
  #
  # PATH pitfall (fixed): `environment = lib.mkForce { ... }` wiped the PATH
  # generated from `path =`, so shutil.which("agent-browser") missed the Nix
  # wrapper and Hermes fell through to `npx agent-browser` (fresh unpatched ELF).
  # Use per-key mkForce and mkBefore so the wrapper is first on PATH.
  systemd.services.hermes-agent = {
    environment = {
      HOME = lib.mkForce cfg.stateDir;
      HERMES_HOME = lib.mkForce "${cfg.stateDir}/.hermes";
      MESSAGING_CWD = lib.mkForce cfg.workingDirectory;
      PUPPETEER_EXECUTABLE_PATH = lib.mkForce "${pkgs.chromium}/bin/chromium";
      CHROME_BIN = lib.mkForce "${pkgs.chromium}/bin/chromium";
    };
    serviceConfig = {
      # Secrets / tool keys (BROWSER_USE_API_KEY, FIRECRAWL_*, etc.) — optional file
      EnvironmentFile = [ "-${cfg.stateDir}/.hermes/.env" ];
      # Unify the parent gateway process cwd into .hermes/workspace as well
      # (delegation workdir controls the chdir for child grok processes).
      WorkingDirectory = lib.mkForce cfg.workingDirectory;
      # config.yaml restart_drain_timeout=180 — unit must allow graceful drain + teardown.
      TimeoutStopSec = lib.mkForce 240;
      # Belt-and-suspenders: re-patch on every start (script uses store-pinned paths,
      # so missing PATH in ExecStartPre is fine). Mid-session drops are handled by
      # the wrapper's patch-before-exec.
      ExecStartPre = [ "${agentBrowserFix}/bin/hermes-browser-fix" ];
    };
    # Wrapper MUST be first so Hermes never prefers raw npm-global ELF or npx.
    path = lib.mkBefore [
      agentBrowserWrapper
      grokWrapper
      pkgs.coreutils
      pkgs.bash
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
      grokWrapper
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

  # IWLA Friday open practice — SignupGenius Playwright signup (Thu 5:59:55 PM ET pre-warm)
  systemd.services.iwla-signup-friday = {
    description = "IWLA Friday open practice SignupGenius automation";
    serviceConfig = {
      Type = "oneshot";
      User = cfg.user;
      Group = cfg.group;
      WorkingDirectory = cfg.workingDirectory;
      ExecStart = "${pkgs.bash}/bin/bash ${cfg.stateDir}/.hermes/skills/artemis/iwla-signupgenius/scripts/signup-friday.sh";
      Environment = [
        "CHROMIUM_PATH=${pkgs.chromium}/bin/chromium"
        "HERMES_HOME=${cfg.stateDir}/.hermes"
        "IWLA_SIGNUP_ENV_FILE=${cfg.stateDir}/.config/iwla-signupgenius.env"
      ];
      TimeoutStartSec = "10min";
    };
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
  };

  systemd.timers.iwla-signup-friday = {
    description = "IWLA Friday SignupGenius signup timer (Thursday 5:59:55 PM ET)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Thu *-*-* 17:59:55 America/New_York";
      Persistent = true;
    };
  };

  };
}

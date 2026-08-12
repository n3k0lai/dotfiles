# Hermes Agent — Nous Research autonomous agent
{ config, pkgs, lib, hermes-agent ? null, ... }:

let
  nodePkg = pkgs.nodejs_24;
  cfg = config.modules.servers.hermes;

  # Optional backends baked into the sealed venv (lazy_deps can't pip-install on Nix).
  # Keep in sync with services.hermes-agent.extraDependencyGroups below (or the
  # withWeb=false package override, which applies the same list).
  hermesDepGroups = [
    "mcp"
    "messaging"
    "edge-tts"
    "firecrawl" # web_search + web_extract via Tool Gateway (or direct)
    # Add "fal" for image/video generation gateway, "exa"/"parallel-web" for other search
    # backends, "modal"/"daytona" for sandboxed code execution delegation, etc. as needed.
  ];

  # Stub web_dist so hermes-agent does not pull the Vite/React hermes-web derivation.
  # Upstream always `ln -s ${hermesWeb}` in installPhase. We rewrite that path after
  # discarding the original string context so Nix never builds hermes-web.
  # (pkgs.replaceDependency still builds the old dep first — useless for memory.)
  hermesWebStub = pkgs.runCommand "hermes-web-disabled" {
    meta.description = "Empty web_dist stub (modules.servers.hermes.withWeb = false)";
  } ''
    mkdir -p "$out"
    cat > "$out/index.html" <<'EOF'
    <!doctype html>
    <meta charset="utf-8">
    <title>Hermes dashboard disabled</title>
    <p>This hermes-agent package was built with <code>withWeb=false</code>.</p>
    EOF
  '';

  # Slim package: same dep groups as the full service, but hermesWeb → stub.
  # Requires hermes-agent flake input (specialArgs on ene/rook).
  #
  # Critical: only drop hermesWeb's string context. Discarding the whole
  # installPhase would also drop hermesTui / venv / skills and break the build
  # (or race on already-realized store paths). getContext keys are .drv paths.
  hermesPackageSlim =
    assert hermes-agent != null
      || throw "modules.servers.hermes.withWeb=false needs hermes-agent in specialArgs";
    let
      system = pkgs.stdenv.hostPlatform.system;
      base = hermes-agent.packages.${system}.default;
      withDeps = base.override { extraDependencyGroups = hermesDepGroups; };
      oldWeb = withDeps.passthru.hermesWeb;
      oldWebOut = builtins.unsafeDiscardStringContext oldWeb.outPath;
      oldWebDrv = builtins.unsafeDiscardStringContext oldWeb.drvPath;
    in
    withDeps.overrideAttrs (old: {
      installPhase =
        let
          phase = old.installPhase;
          # Rewrite the symlink target in the script text.
          rewritten =
            builtins.replaceStrings [ oldWebOut ] [ (builtins.unsafeDiscardStringContext hermesWebStub.outPath) ]
              (builtins.unsafeDiscardStringContext phase);
          # Keep every original input except hermesWeb; add the stub.
          ctx = builtins.removeAttrs (builtins.getContext phase) [ oldWebDrv ];
          stubCtx = builtins.getContext "${hermesWebStub}";
        in
        builtins.appendContext rewritten (ctx // stubCtx);
      passthru = old.passthru // {
        hermesWeb = hermesWebStub;
      };
    });

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

    # PATH for interactive login is owned by hermes-shell-profile activation
    # (managed .profile / .bash_profile). No append-only mutation here.
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
      # Interactive PATH (npm-global) is owned by hermes-shell-profile activation.
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

  # Interactive login profile for `sudo -i -u hermes` / ene|rook shell.
  # Login shell stays bash (services use explicit ExecStart; no fish).
  hermesBashProfile = pkgs.writeText "hermes-bash-profile" ''
    # Managed by modules/servers/hermes.nix — regenerated on nixos-rebuild.
    # Marker: HERMES_NIX_PROFILE=1
    export HERMES_NIX_PROFILE=1
    export HOME="${cfg.stateDir}"
    export USER="''${USER:-hermes}"
    export HERMES_HOME="${cfg.stateDir}/.hermes"
    # Grok CLI + npm-global agent-browser ahead of system PATH
    export PATH="$HOME/.grok/bin:$HOME/.npm-global/bin:$PATH"

    # Interactive login only (sudo -i, ene shell, rook shell)
    case $- in
      *i*)
        if [ -d "$HERMES_HOME" ]; then
          cd "$HERMES_HOME" || true
        fi
        PS1='[hermes \w]\$ '
        ;;
    esac
  '';
in
{
  options.modules.servers.hermes = {
    enable = lib.mkEnableOption "Hermes Agent";
    user = lib.mkOption {
      type = lib.types.str;
      default = "hermes";
      description = "System user for Hermes services (gateway, optional dashboard)";
    };
    group = lib.mkOption {
      type = lib.types.str;
      default = "users";
      description = "Primary group for Hermes service processes";
    };
    envFile = lib.mkOption {
      type = lib.types.path;
      default = ./secrets/hermes_env.age;
      description = "Path to the agenix-encrypted env file for Hermes";
    };
    # hermes_ssh_config.age was historically ene-only; rook must opt in after re-encrypt.
    enableSshConfig = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Decrypt modules/servers/secrets/hermes_ssh_config.age to ~/.ssh/config.
        Recipients must include this host's SSH host key (see secrets.nix).
        Set false on hosts not yet in the age recipients list (avoids agenixInstall fail).
      '';
    };
    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/hermes";
      description = "State directory for Hermes";
    };
    workingDirectory = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/hermes/.hermes/workspace";
      description = "Working directory for the Hermes gateway (and dashboard, if enabled)";
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
    # Runtime: systemd units. Default on for hosts that still use the web UI (rook).
    dashboard.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Run `hermes dashboard` on 127.0.0.1:9119 (plus optional Tailscale Serve).
        Disable on gateway/CLI-only hosts (e.g. ene: Discord + SSH). This only
        stops the units — set withWeb = false to also skip building hermes-web.
      '';
    };
    # Build graph: hermes-web Vite assets. Independent of dashboard.enable.
    withWeb = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Include hermes-web (Vite dashboard) in the hermes-agent package.
        false rewrites installPhase to an empty stub (string-context discarded) so
        Nix never builds the multi-GB npm web derivation. Use on 4 GiB hosts that
        only need gateway + CLI. Requires hermes-agent flake specialArgs.
      '';
    };
    tailscaleServe = {
      enable = lib.mkEnableOption ''
        Expose the Hermes dashboard on the tailnet via Tailscale Serve (MagicDNS).
        Access at https://<hostname>.<tailnet>.ts.net — not on the public internet.
        Requires dashboard.enable = true.
      '';
      target = lib.mkOption {
        type = lib.types.str;
        default = toString serveProxyPort;
        description = "Local port passed to tailscale serve (via Host-rewrite proxy, not dashboard directly).";
      };
    };

    # A2A (Agent-to-Agent) — inbound HTTP + outbound peer tools.
    # Secrets (A2A_PEER_TOKENS, A2A_OUTBOUND_TOKEN_*) live in envFile (agenix).
    # Non-secret bind/name/url + peer URLs are declarative here.
    # Docs: https://hermes-agent.nousresearch.com/docs/user-guide/messaging/a2a
    a2a = {
      enable = lib.mkEnableOption "Hermes A2A inbound server + outbound peer tools";
      port = lib.mkOption {
        type = lib.types.port;
        default = 9900;
        description = "A2A HTTP listen port";
      };
      host = lib.mkOption {
        type = lib.types.str;
        default = "0.0.0.0";
        description = ''
          Bind address. Non-localhost requires A2A_PEER_TOKENS (or A2A_BEARER_TOKEN)
          in the hermes env secret — Hermes refuses to widen without a token.
        '';
      };
      agentName = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Name on the Agent Card (A2A_AGENT_NAME). Default: hostname-derived.";
      };
      publicUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Routable URL advertised on the Agent Card (MagicDNS, e.g. http://ene.tailnet:9900).";
      };
      trustedPeers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Allow-list of authenticated peer identities (A2A_TRUSTED_PEERS).";
      };
      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Open TCP a2a.port on tailscale0 (tailnet-only; not the public internet).";
      };
      peers = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
          options = {
            url = lib.mkOption {
              type = lib.types.str;
              description = "Peer A2A base URL (e.g. http://rook.bushbaby-mercat.ts.net:9900).";
            };
            capabilities = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Capability tags advertised for a2a_orchestrate.";
            };
            timeout = lib.mkOption {
              type = lib.types.int;
              default = 120;
              description = "Outbound call timeout (seconds).";
            };
            outboundTokenEnv = lib.mkOption {
              type = lib.types.str;
              default = "A2A_OUTBOUND_TOKEN_${lib.toUpper name}";
              defaultText = lib.literalExpression ''"A2A_OUTBOUND_TOKEN_<PEER>"'';
              description = ''
                Env var (in hermes envFile) holding the bearer token this host
                presents when calling the peer. Must match the peer's
                A2A_PEER_TOKENS entry for this agent name.
              '';
            };
          };
        }));
        default = { };
        description = "Outbound peers (a2a_agents). Tokens come from env, not Nix.";
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

    # Secrets (decrypted at activation by agenix).
    # SoT is modules/servers/secrets/hermes_env.age (secrets.nix → ene + nicho).
    # Owner MUST be hermes so the hermes-agent-setup seeder can cat this file.
    # Do NOT tell operators to echo keys into ~/.hermes/.env — edit the age blob.
    #
    # CRITICAL: do NOT set path = "${stateDir}/.hermes/.env".
    # Upstream hermes-agent-setup does:
    #   install -m 0640 /dev/null $HERMES_HOME/.env   # truncate
    #   cat Nix environment >> .env
    #   cat each environmentFiles >> .env
    # If environmentFiles points at the same path as .env, the truncate wipes the
    # age secret and `cat file >> file` fails (gen 105 / 2026-08-05 outage:
    # Discord token gone, gateway a2a-only, activation hermes-agent-setup exit 1).
    # Default agenix path /run/agenix/hermes-env is the correct source; the seeder
    # materializes the merged result at $HERMES_HOME/.env for EnvironmentFile=.
    age.secrets.hermes-env = {
      file = cfg.envFile;
      owner = cfg.user;
      group = cfg.user;
      mode = "0400";
    };

    age.secrets.hermes-ssh-config = lib.mkIf cfg.enableSshConfig {
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
    # Package comes from hermes-agent.nixosModules.default (flake input), unless
    # withWeb=false — then we substitute a slim package (hermesWeb → stub) so the
    # Vite web UI is not built. Do not override nodejs_*: as of v0.20+ the package
    # builds against nodejs_26 + npm 12 internally and no longer accepts nodejs_22.
    #
    # Soul owns most agent config (model, discord, MCP, …). Upstream deep-merges
    # `settings` into config.yaml on activation (Nix keys win; soul keys preserved).
    # We only declare A2A platform enable here; peers/tokens land via hermes-a2a-config.
    settings = lib.mkIf cfg.a2a.enable {
      gateway.platforms.a2a = {
        enabled = true;
        extra.port = cfg.a2a.port;
      };
    };
    # Non-secret A2A bind/name/url → $HERMES_HOME/.env (merged with age secrets).
    environment = lib.mkIf cfg.a2a.enable (
      {
        A2A_HOST = cfg.a2a.host;
        A2A_PORT = toString cfg.a2a.port;
      }
      // lib.optionalAttrs (cfg.a2a.agentName != null) {
        A2A_AGENT_NAME = cfg.a2a.agentName;
      }
      // lib.optionalAttrs (cfg.a2a.publicUrl != null) {
        A2A_PUBLIC_URL = cfg.a2a.publicUrl;
      }
      // lib.optionalAttrs (cfg.a2a.trustedPeers != [ ]) {
        A2A_TRUSTED_PEERS = lib.concatStringsSep "," cfg.a2a.trustedPeers;
      }
    );
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

    # When withWeb=false the slim package already bakes in hermesDepGroups; leave
    # extraDependencyGroups empty so the upstream module does not call .override
    # again (groups already applied; a second override would rebuild with web).
    package = lib.mkIf (!cfg.withWeb) hermesPackageSlim;
    extraDependencyGroups = lib.mkIf cfg.withWeb hermesDepGroups;
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

  # Managed interactive bash profile for the hermes service user.
  system.activationScripts.hermes-shell-profile = lib.stringAfter [ "users" "groups" ] ''
    PROF="${cfg.stateDir}/.profile"
    BPROF="${cfg.stateDir}/.bash_profile"
    install -d -m 0755 -o ${cfg.user} -g ${cfg.user} "${cfg.stateDir}"
    install -m 0644 ${hermesBashProfile} "$PROF"
    install -m 0644 ${hermesBashProfile} "$BPROF"
    chown ${cfg.user}:${cfg.user} "$PROF" "$BPROF"
  '';

  # Run grok CLI provisioning on every activation (so delegated grok-build* agents work).
  system.activationScripts.hermes-grok-provision = lib.stringAfter [ "users" "groups" "hermes-workspace" "hermes-shell-profile" ] ''
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

  # A2A: merge outbound peers + enable a2a toolset in soul config.yaml.
  # Tokens read from $HERMES_HOME/.env after hermes-agent-setup merges the age
  # secret (A2A_OUTBOUND_TOKEN_*, A2A_PEER_TOKENS). Missing keys warn on stderr
  # but must not hard-fail activation — Discord/API keys already landed in .env.
  # Runs after hermes-agent-setup (which writes .env) and dynamic-config.
  system.activationScripts.hermes-a2a-config = lib.mkIf cfg.a2a.enable (
    let
      peersJson = pkgs.writeText "hermes-a2a-peers.json" (builtins.toJSON (
        lib.mapAttrs (_name: p: {
          inherit (p) url capabilities timeout outboundTokenEnv;
        }) cfg.a2a.peers
      ));
      a2aMerge = pkgs.writeScript "hermes-a2a-merge" ''
        #!${pkgs.python3.withPackages (ps: [ ps.pyyaml ])}/bin/python3
        import os, sys, json, yaml
        from pathlib import Path

        config_path = Path(sys.argv[1])
        peers_path = Path(sys.argv[2])
        env_path = Path(sys.argv[3])
        port = int(sys.argv[4])

        def load_env(path: Path) -> dict:
            out = {}
            if not path.exists():
                return out
            for line in path.read_text().splitlines():
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, _, v = line.partition("=")
                out[k.strip()] = v.strip().strip("'").strip('"')
            return out

        peers_spec = json.loads(peers_path.read_text())
        env = load_env(env_path)

        cfg = {}
        if config_path.exists():
            with open(config_path) as f:
                cfg = yaml.safe_load(f) or {}

        # Inbound platform (also set via services.hermes-agent.settings; re-assert)
        gw = cfg.setdefault("gateway", {})
        plats = gw.setdefault("platforms", {})
        a2a = plats.setdefault("a2a", {})
        a2a["enabled"] = True
        extra = a2a.setdefault("extra", {})
        extra["port"] = port

        # Outbound peers
        agents = cfg.setdefault("a2a_agents", {})
        missing = []
        for name, spec in peers_spec.items():
            token_env = spec.get("outboundTokenEnv") or f"A2A_OUTBOUND_TOKEN_{name.upper()}"
            token = env.get(token_env, "")
            if not token:
                missing.append(token_env)
            entry = agents.get(name) if isinstance(agents.get(name), dict) else {}
            entry["url"] = spec["url"]
            entry["timeout"] = spec.get("timeout", 120)
            if spec.get("capabilities"):
                entry["capabilities"] = list(spec["capabilities"])
            if token:
                entry["auth"] = {"type": "bearer", "token": token}
            agents[name] = entry

        # Enable a2a toolset on known platform profiles (append, never wipe)
        pts = cfg.setdefault("platform_toolsets", {})
        if isinstance(pts, dict):
            for _plat, tools in pts.items():
                if isinstance(tools, list) and "a2a" not in tools:
                    tools.append("a2a")

        # If top-level toolsets is a list without a2a and without "all", append
        ts = cfg.get("toolsets")
        if isinstance(ts, list) and "all" not in ts and "a2a" not in ts:
            ts.append("a2a")

        # Drop a2a from disabled_toolsets if present
        agent = cfg.get("agent")
        if isinstance(agent, dict):
            disabled = agent.get("disabled_toolsets")
            if isinstance(disabled, list) and "a2a" in disabled:
                agent["disabled_toolsets"] = [x for x in disabled if x != "a2a"]

        with open(config_path, "w") as f:
            yaml.dump(cfg, f, default_flow_style=False, sort_keys=False)

        if missing:
            print(
                "hermes-a2a-config: missing outbound token env vars (add to hermes env age secret): "
                + ", ".join(missing),
                file=sys.stderr,
            )
        else:
            print(f"hermes-a2a-config: merged {len(peers_spec)} peer(s) into {config_path}")
      '';
    in
    lib.stringAfter [ "hermes-agent-setup" "hermes-dynamic-config" ] ''
      ${a2aMerge} \
        ${cfg.stateDir}/.hermes/config.yaml \
        ${peersJson} \
        ${cfg.stateDir}/.hermes/.env \
        ${toString cfg.a2a.port}
      chown ${cfg.user}:${cfg.group} ${cfg.stateDir}/.hermes/config.yaml 2>/dev/null || true
      chmod 0660 ${cfg.stateDir}/.hermes/config.yaml 2>/dev/null || true
    ''
  );

  # Tailnet-only A2A port (ene has a strict public allow-list; rook trusts tailscale0)
  networking.firewall.interfaces.tailscale0.allowedTCPPorts =
    lib.mkIf (cfg.a2a.enable && cfg.a2a.openFirewall) [ cfg.a2a.port ];

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
      # Merged env: upstream hermes-agent-setup writes $HERMES_HOME/.env from
      # services.hermes-agent.environment + age secret (/run/agenix/hermes-env).
      # Optional .env.local for non-secret local overrides only (ignored if missing).
      # Never point age.secrets.hermes-env.path at .env — see age.secrets comment.
      EnvironmentFile = [
        "-${cfg.stateDir}/.hermes/.env"
        "-${cfg.stateDir}/.hermes/.env.local"
      ];
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


  # Hermes dashboard — web UI for managing agent config, sessions, logs.
  # ene: dashboard.enable=false (Discord + SSH CLI only). rook: still on by default.
  systemd.services.hermes-dashboard = lib.mkIf cfg.dashboard.enable {
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
  systemd.services.hermes-dashboard-serve-proxy = lib.mkIf (cfg.dashboard.enable && cfg.tailscaleServe.enable) {
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
  systemd.services.hermes-dashboard-tailscale-serve = lib.mkIf (cfg.dashboard.enable && cfg.tailscaleServe.enable) {
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

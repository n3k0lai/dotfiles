# modules/servers/static-sites.nix
# Pull-based static site deploys. Site versions are NOT pinned in Nix: each site
# follows a git branch, and a timer rebuilds it whenever the branch moves.
#
# Per site <name>:
#   - system user/group static-site-<name>; caddy joins the group (read-only).
#   - static-site-<name>.service (oneshot): anonymous https fetch of `branch`
#     into /var/lib/static-sites/<name>/repo (bare). If the branch head differs
#     from the deployed sha, export it into a scratch dir, run buildCommand,
#     move outDir to releases/<shortsha>, then atomically repoint `current`
#     (ln -sfn + mv -T). Keeps the newest `keepReleases`. A failed build leaves
#     `current` alone and is not retried until a new commit lands (or the
#     failed-sha file is removed).
#   - static-site-<name>.timer: shortly after activation, then every `interval`.
#   - Manual deploy:  systemctl start static-site-<name>
#   - Status/logs:    systemctl status static-site-<name>; journalctl -u static-site-<name>
#   - Deployed sha:   /var/lib/static-sites/<name>/deployed-sha
#   - Caddy vhost:    root * /var/lib/static-sites/<name>/current (if domain set)
{ config, lib, pkgs, ... }:

let
  inherit (lib) mkOption types mapAttrs' nameValuePair mapAttrsToList filterAttrs;
  cfg = config.services.staticSites;
  stateRoot = "/var/lib/static-sites";

  deployScript = name: site: pkgs.writeShellScript "static-site-${name}-deploy" ''
    set -euo pipefail
    state=${stateRoot}/${name}
    repo=$state/repo
    url=${lib.escapeShellArg site.repo}
    branch=${lib.escapeShellArg site.branch}

    mkdir -p "$state/releases" "$state/home"

    if [ ! -f "$repo/HEAD" ]; then
      rm -rf "$repo"
      git init --quiet --bare "$repo"
    fi
    git -C "$repo" fetch --quiet --depth=1 --no-tags "$url" "+refs/heads/$branch:refs/heads/$branch"
    sha=$(git -C "$repo" rev-parse "refs/heads/$branch")
    short=''${sha:0:12}

    deployed=$(cat "$state/deployed-sha" 2>/dev/null || true)
    if [ "$sha" = "$deployed" ] && [ -e "$state/current" ]; then
      echo "up to date at $short"
      exit 0
    fi
    if [ "$sha" = "$(cat "$state/failed-sha" 2>/dev/null || true)" ]; then
      echo "$short failed to build before; skipping (rm $state/failed-sha to retry)"
      exit 0
    fi

    echo "deploying $branch @ $short (was ''${deployed:0:12})"
    work=$(mktemp -d "$state/build.XXXXXX")
    trap 'rm -rf "$work"' EXIT
    mkdir "$work/src"
    git -C "$repo" archive "$sha" | tar -x -C "$work/src"

    if ! (cd "$work/src" && bash -euo pipefail -c ${lib.escapeShellArg site.buildCommand}); then
      echo "$sha" > "$state/failed-sha"
      echo "build of $short failed; current release left live" >&2
      exit 1
    fi
    out="$work/src/"${lib.escapeShellArg site.outDir}
    if [ ! -d "$out" ]; then
      echo "$sha" > "$state/failed-sha"
      echo "build of $short produced no ${site.outDir}/; current release left live" >&2
      exit 1
    fi

    rel=$state/releases/$short
    rm -rf "$rel"
    mv -T "$out" "$rel"
    chmod -R g+rX,o-rwx "$rel"

    ln -sfn "releases/$short" "$state/current.new"
    mv -T "$state/current.new" "$state/current"
    echo "$sha" > "$state/deployed-sha.new"
    mv -T "$state/deployed-sha.new" "$state/deployed-sha"
    rm -f "$state/failed-sha"
    echo "live: $short"

    # Prune old releases (newest first), never the live one.
    live=$(readlink "$state/current")
    ls -1dt "$state"/releases/*/ | tail -n +$(( ${toString site.keepReleases} + 1 )) | while read -r old; do
      [ "releases/$(basename "$old")" = "$live" ] || rm -rf "$old"
    done
  '';

  siteOpts = { name, ... }: {
    options = {
      repo = mkOption {
        type = types.str;
        example = "https://github.com/n3k0lai/bruhxd.git";
        description = "Public https git URL (fetched anonymously).";
      };
      branch = mkOption { type = types.str; default = "main"; };
      buildCommand = mkOption {
        type = types.str;
        default = "npm ci && npx vite build";
        description = "Run with bash in the checkout. Use \":\" for prebuilt sites.";
      };
      outDir = mkOption {
        type = types.str;
        default = "dist";
        description = "Directory (relative to the checkout) that gets served.";
      };
      domain = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Caddy virtual host to serve `current` on (null = no vhost).";
      };
      extraCaddyConfig = mkOption { type = types.lines; default = ""; };
      interval = mkOption { type = types.str; default = "5min"; };
      keepReleases = mkOption { type = types.ints.positive; default = 3; };
      packages = mkOption {
        type = types.listOf types.package;
        default = [ pkgs.nodejs ];
        description = "Extra build tools on PATH (git, bash, coreutils are always there).";
      };
    };
  };
in
{
  options.services.staticSites = mkOption {
    type = types.attrsOf (types.submodule siteOpts);
    default = { };
    description = "Static sites deployed by pulling a git branch on a timer.";
  };

  config = lib.mkIf (cfg != { }) {
    users.users = (mapAttrs' (name: _: nameValuePair "static-site-${name}" {
      isSystemUser = true;
      group = "static-site-${name}";
      home = "${stateRoot}/${name}";
    }) cfg) // {
      caddy.extraGroups = mapAttrsToList (name: _: "static-site-${name}") cfg;
    };
    users.groups = mapAttrs' (name: _: nameValuePair "static-site-${name}" { }) cfg;

    systemd.services = mapAttrs' (name: site: nameValuePair "static-site-${name}" {
      description = "Pull and build static site ${name}";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      path = [ pkgs.git pkgs.bash pkgs.coreutils pkgs.gnutar ] ++ site.packages;
      environment = {
        HOME = "${stateRoot}/${name}/home";
        npm_config_cache = "/var/cache/static-sites/${name}/npm";
        npm_config_update_notifier = "false";
        npm_config_fund = "false";
        npm_config_audit = "false";
        GIT_TERMINAL_PROMPT = "0";
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = deployScript name site;
        User = "static-site-${name}";
        Group = "static-site-${name}";
        StateDirectory = "static-sites/${name}";
        StateDirectoryMode = "0750"; # caddy reads via group
        CacheDirectory = "static-sites/${name}";
        UMask = "0027";
        TimeoutStartSec = "30min";
        Nice = 10;
        IOSchedulingClass = "idle";

        # Hardening (network stays on for git + npm).
        ProtectSystem = "strict";
        ReadWritePaths = [ "${stateRoot}/${name}" "/var/cache/static-sites/${name}" ];
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
        AmbientCapabilities = "";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectHostname = true;
        ProtectProc = "invisible";
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [ "@system-service" ];
        # MemoryDenyWriteExecute stays off: node's JIT needs W+X pages.
      };
    }) cfg;

    systemd.timers = mapAttrs' (name: site: nameValuePair "static-site-${name}" {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnActiveSec = "30s";
        OnUnitActiveSec = site.interval;
        RandomizedDelaySec = "30s";
      };
    }) cfg;

    services.caddy.virtualHosts = mapAttrs' (name: site: nameValuePair site.domain {
      extraConfig = ''
        root * ${stateRoot}/${name}/current
        file_server
        ${site.extraCaddyConfig}
      '';
    }) (filterAttrs (_: site: site.domain != null) cfg);
  };
}

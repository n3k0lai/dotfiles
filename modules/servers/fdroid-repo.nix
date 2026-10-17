# Private F-Droid repo for my own Android builds (horology, waves, nanoloop,
# magination). The Fold (and later the rest of the phone drawer) installs and
# updates them from here with Droid-ify + Shizuku.
#
# Tailnet only: `tailscale serve` terminates HTTPS for <host>.<tailnet>.ts.net
# with the tailnet cert and maps /fdroid/repo onto the repo dir. On ene this
# sits next to Caddy: serve only claims :443 on the tailnet address (tailscaled
# handles it in-process, the same way the old Hermes dashboard serve did), so
# Caddy's public :443 sites are untouched and the repo is never on the public IP.
#
# Flow: Grok Bot's box scp's <pkg>_<versionCode>.apk, then a .json manifest,
# into `inbox` as an `uploaders` member (grokbot-ene; no sudo). A path unit
# fires the ingest as the fdroid user: it re-checks the sha256, the pinned
# signing cert, the versionCode and free disk, moves the APK into the repo,
# writes the changelog, and runs `fdroid update` to sign the index. The repo
# signing key is generated on first run in dataDir/secrets (0600, never in the
# nix store).
#
#   fdroid-repo-info                          # URL, fingerprint, add-repo QR
#   journalctl -u fdroid-repo-ingest -n 50    # what got published or rejected
#   cat /var/lib/fdroid-repo/status/<pkg>_<versionCode>
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.modules.servers.fdroid-repo;

  repoUrl = "https://${cfg.hostName}${cfg.urlPath}/repo";
  pinsFile = pkgs.writeText "fdroid-repo-pins.json" (builtins.toJSON cfg.pins);
  tailscale = "${config.services.tailscale.package}/bin/tailscale";

  tools = with pkgs; [
    fdroidserver
    apksigner
    jdk_headless # keytool + jarsigner for the repo key and index signing
    jq
    coreutils
    findutils
    gnused
    gnugrep
  ];

  mkScript = name: file: pkgs.writeShellApplication {
    name = "fdroid-repo-${name}";
    runtimeInputs = tools;
    text = builtins.readFile file;
  };
  fetchInbox = mkScript "fetch-inbox" ./fdroid-repo/fetch-inbox.sh;
  setup = mkScript "setup" ./fdroid-repo/setup.sh;
  ingest = mkScript "ingest" ./fdroid-repo/ingest.sh;

  info = pkgs.writeShellApplication {
    name = "fdroid-repo-info";
    runtimeInputs = with pkgs; [ qrencode coreutils systemd ];
    text = ''
      fp="$(cat ${cfg.dataDir}/FINGERPRINT 2>/dev/null || true)"
      echo "Repo URL:     ${repoUrl}"
      if [ -z "$fp" ]; then
        echo "Fingerprint:  not generated yet. Run: sudo systemctl start fdroid-repo-ingest"
        exit 0
      fi
      link="fdroidrepos://${cfg.hostName}${cfg.urlPath}/repo?fingerprint=$fp"
      echo "Fingerprint:  $fp"
      echo "Add link:     $link"
      echo "Last publish: $(cat ${cfg.dataDir}/LAST_PUBLISH 2>/dev/null || echo never)"
      echo
      echo "Scan with the phone camera (opens Droid-ify / F-Droid):"
      qrencode -t ansiutf8 "$link"
    '';
  };
in {
  options.modules.servers.fdroid-repo = {
    enable = mkEnableOption "private F-Droid repo served on the tailnet";

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/fdroid-repo";
      description = "fdroid working dir: repo/, archive/, metadata/, secrets/ (signing key).";
    };

    inbox = mkOption {
      type = types.str;
      default = "${cfg.dataDir}/inbox";
      defaultText = literalExpression ''"''${dataDir}/inbox"'';
      description = "Setgid upload dir (group `inboxGroup`, 2770). Uploaders put <pkg>_<vc>.apk + .json here.";
    };

    inboxGroup = mkOption {
      type = types.str;
      default = "fdroid-inbox";
      description = "Group allowed to write the inbox. Add uploader accounts to it (e.g. grokbot-ene's extraGroups).";
    };

    minFreeMB = mkOption {
      type = types.ints.unsigned;
      default = 2048;
      description = "Reject uploads that would leave less than this much free disk on the data dir's filesystem.";
    };

    hostName = mkOption {
      type = types.str;
      default = "${config.networking.hostName}.bushbaby-mercat.ts.net";
      defaultText = literalExpression ''"''${networking.hostName}.bushbaby-mercat.ts.net"'';
      description = "MagicDNS name the repo is served on (needs HTTPS certs enabled on the tailnet).";
    };

    urlPath = mkOption {
      type = types.str;
      default = "/fdroid";
      description = "Path prefix. The repo is at <urlPath>/repo, the archive at <urlPath>/archive.";
    };

    httpsPort = mkOption {
      type = types.port;
      default = 443;
      description = "tailscale serve HTTPS port.";
    };

    repoName = mkOption {
      type = types.str;
      default = "kiss";
      description = "Repo name shown in Droid-ify.";
    };

    repoDescription = mkOption {
      type = types.str;
      default = "Nicholai's own Android builds, served from kiss over the tailnet.";
    };

    keepVersions = mkOption {
      type = types.ints.positive;
      default = 3;
      description = "Versions per app kept in the main repo (fdroid archive_older). Older ones move to the archive.";
    };

    keepArchived = mkOption {
      type = types.ints.unsigned;
      default = 2;
      description = "Versions per app kept in the archive repo; older APKs are deleted.";
    };

    pins = mkOption {
      type = types.attrsOf types.str;
      default = {
        # Horology Bench: horology-bench.p12 (same cert as the box debug key M1.0-M1.8 used).
        "app.horology.bench" = "c2ff307dd3354d95040517ed66f1b5005abe15ce228b5b8b5a76d823adaf662c";
        # Waves: provisional, still the box debug key. Changes once its own key exists.
        "sh.comfy.waves" = "c2ff307dd3354d95040517ed66f1b5005abe15ce228b5b8b5a76d823adaf662c";
      };
      description = ''
        package name -> SHA-256 of the only signing cert allowed for it
        (apksigner verify --print-certs). APKs signed by anything else are rejected.
      '';
    };

    allowUnpinned = mkOption {
      type = types.bool;
      default = false;
      description = "Accept packages that have no entry in `pins` (not recommended).";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.fdroidserver info ];

    users.users.fdroid = {
      isSystemUser = true;
      group = "fdroid";
      extraGroups = [ cfg.inboxGroup ];
      home = cfg.dataDir;
      description = "Private F-Droid repo";
    };
    users.groups.fdroid = { };
    users.groups.${cfg.inboxGroup} = { };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 fdroid fdroid - -"
      "d ${cfg.dataDir}/secrets 0700 fdroid fdroid - -"
      "d ${cfg.dataDir}/incoming 0750 fdroid fdroid - -"
      "d ${cfg.dataDir}/repo 0755 fdroid fdroid - -"
      "d ${cfg.dataDir}/archive 0755 fdroid fdroid - -"
      "d ${cfg.dataDir}/status 0755 fdroid fdroid - -"
      # setgid + group-writable, no sticky bit: uploaders write, fdroid moves files out.
      "d ${cfg.inbox} 2770 fdroid ${cfg.inboxGroup} - -"
    ];

    systemd.services.fdroid-repo-ingest = {
      description = "Publish APKs from the inbox into the private F-Droid repo";
      after = [ "local-fs.target" ];
      environment = {
        HOME = cfg.dataDir;
        DATA_DIR = cfg.dataDir;
        INBOX = cfg.inbox;
        MIN_FREE_MB = toString cfg.minFreeMB;
        JAVA_TOOL_OPTIONS = "-Xmx384m";
        REPO_URL = repoUrl;
        REPO_NAME = cfg.repoName;
        REPO_DESC = cfg.repoDescription;
        ARCHIVE_OLDER = toString cfg.keepVersions;
        KEEP_ARCHIVED = toString cfg.keepArchived;
        KEY_DNAME = "CN=${cfg.repoName} F-Droid repo, O=Nicholai";
        PINS_FILE = "${pinsFile}";
        ALLOW_UNPINNED = if cfg.allowUnpinned then "1" else "0";
      };
      serviceConfig = {
        Type = "oneshot";
        User = "fdroid";
        Group = "fdroid";
        WorkingDirectory = cfg.dataDir;
        ExecStartPre = [
          "${fetchInbox}/bin/fdroid-repo-fetch-inbox"
          "${setup}/bin/fdroid-repo-setup"
        ];
        ExecStart = "${ingest}/bin/fdroid-repo-ingest";
        TimeoutStartSec = "15min";
        Nice = 10;
        IOSchedulingClass = "idle";
        # ene has 4 GB shared with Minecraft + Hermes; cap the JVM signing steps.
        MemoryMax = "768M";

        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ cfg.dataDir ];
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        # No MemoryDenyWriteExecute: the JVM (keytool/jarsigner/apksigner) JITs.
      };
    };

    # Fires whenever something lands in (or leaves) the inbox.
    systemd.paths.fdroid-repo-ingest = {
      description = "Watch the F-Droid repo inbox";
      wantedBy = [ "paths.target" ];
      pathConfig = {
        PathChanged = cfg.inbox;
        Unit = "fdroid-repo-ingest.service";
      };
    };

    # Backstop: first run after boot (creates the key + empty index), then every 15 min.
    systemd.timers.fdroid-repo-ingest = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "15min";
      };
    };

    # tailscale serve: https://<hostName><urlPath>/{repo,archive} -> dataDir/{repo,archive}.
    # tailscaled (root) reads the files directly; secrets/ and config.yml are never mapped.
    systemd.services.fdroid-repo-serve = {
      description = "Serve the private F-Droid repo on the tailnet (tailscale serve)";
      after = [ "tailscaled.service" "network-online.target" ];
      wants = [ "tailscaled.service" "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure"; # tailscaled may not be logged in yet at boot
        RestartSec = 20;
        ExecStart = [
          "${tailscale} serve --bg --https=${toString cfg.httpsPort} --set-path=${cfg.urlPath}/repo ${cfg.dataDir}/repo"
          "${tailscale} serve --bg --https=${toString cfg.httpsPort} --set-path=${cfg.urlPath}/archive ${cfg.dataDir}/archive"
        ];
        ExecStop = [
          "-${tailscale} serve --https=${toString cfg.httpsPort} --set-path=${cfg.urlPath}/repo off"
          "-${tailscale} serve --https=${toString cfg.httpsPort} --set-path=${cfg.urlPath}/archive off"
        ];
      };
    };

    # tailscale serve answers on the tailnet address only. (On ene 443 is already
    # open publicly for Caddy; this keeps the rule explicit if that ever changes.)
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ cfg.httpsPort ];
  };
}

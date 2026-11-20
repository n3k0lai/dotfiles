# Matrix on ene: Tuwunel homeserver, mautrix-gmessages (Google Messages
# SMS/RCS) bridge, and a self-hosted Element Web with the waves theme.
#
# Plan + runbook: vault Projects/matrix-bridge/PLAN.md
#
# - Client API only, public at https://<publicHost> through Caddy. Federation
#   is off and :8448 stays closed.
# - Registration needs the token in tuwunel_registration_token.age. Without
#   that file registration stays closed.
# - Bridges: matrix-appservice-registrations.service (root, before tuwunel)
#   generates each bridge's registration.yaml once. Tuwunel gets the files via
#   LoadCredential (its unit uses DynamicUser + PrivateUsers, so shared groups
#   don't work) and reads them from appservice_dir. A new bridge needs one
#   `systemctl restart tuwunel`.
# - mautrix-gmessages is taken from nixpkgs-unstable but pinned to upstream
#   v0.2611.0 (the flake lock is from 2026-05-31 and still has v0.2605.0).
#   The pin is an overrideAttrs on the package only; the lock is not updated.
# - mautrix-instagram (Instagram DMs) is built from the mautrix/meta repo
#   (cmd/mautrix-instagram, v0.2611.0) on top of nixpkgs' mautrix-meta
#   package. Since v26.08 mautrix-meta itself no longer does Instagram, so
#   nixpkgs' services.mautrix-meta "instagram" mode doesn't apply.
{ config, pkgs, lib, pkgs-unstable, ... }:

with lib;

let
  cfg = config.modules.servers.matrix;
  twPort = 6167;
  credDir = "/run/credentials/tuwunel.service";

  secretsDir = ./secrets;
  regTokenFile = secretsDir + "/tuwunel_registration_token.age";
  gmEnvFile = secretsDir + "/mautrix_gmessages_env.age";
  hasRegToken = builtins.pathExists regTokenFile;
  hasGmEnv = builtins.pathExists gmEnvFile;
  gmOn = cfg.gmessages.enable && hasGmEnv;
  igEnvFile = secretsDir + "/mautrix_instagram_env.age";
  hasIgEnv = builtins.pathExists igEnvFile;
  igOn = cfg.instagram.enable && hasIgEnv;
  anyBridge = gmOn || igOn;

  # ---------- mautrix-gmessages ----------
  gm = rec {
    # Pinned to upstream v0.2611.0 (2026-11-16). The flake's nixpkgs-unstable
    # lock is from 2026-05-31 and still has v0.2605.0; overrideAttrs here
    # rather than updating the lock (which would also move kiss's unstable
    # packages).
    # goolm = mautrix's pure-Go Olm. Default libolm is marked insecure in
    # nixpkgs (deprecated upstream, side-channel issues) and would need
    # permittedInsecurePackages = [ "olm-3.2.16" ] instead.
    pkg = (pkgs-unstable.mautrix-gmessages.override { withGoolm = true; }).overrideAttrs (o: rec {
      version = "26.11";
      tag = "v0.2611.0";
      src = pkgs-unstable.fetchFromGitHub {
        owner = "mautrix";
        repo = "gmessages";
        inherit tag;
        hash = "sha256-Z7Hv8OkQ1qbOLvQ11Vp9ssDXMT/V9Gva+S4eoDh7NgE=";
      };
      vendorHash = "sha256-y2RHc948wDe+LTi8J+Nc7v43kIWsMO9mFVkDSOFKImU=";
      ldflags = [
        "-s"
        "-w"
        "-X"
        "main.Tag=${tag}"
      ];
    });
    dataDir = "/var/lib/mautrix-gmessages";
    port = 29336;
    config = "${dataDir}/config.yaml";
    registration = "${dataDir}/registration.yaml";
  };
  gmSettings = {
    homeserver = {
      address = "http://127.0.0.1:${toString twPort}";
      domain = cfg.serverName;
      software = "standard";
    };
    appservice = {
      address = "http://127.0.0.1:${toString gm.port}";
      hostname = "127.0.0.1";
      port = gm.port;
      id = "gmessages";
      bot = {
        username = "gmessagesbot";
        displayname = "Texts";
      };
      username_template = "gmessages_{{.}}";
      as_token = ""; # copied from the generated registration in preStart
      hs_token = "";
    };
    database = {
      type = "sqlite3-fk-wal";
      uri = "file:${gm.dataDir}/gmessages.db?_txlock=immediate";
    };
    network = {
      displayname_template = "{{or .FullName .PhoneNumber}}";
      device_meta = {
        os = "comfy";
        browser = "OTHER";
        type = "TABLET"; # coexists with one messages.google.com tab
      };
      aggressive_reconnect = false;
      initial_chat_sync_count = 100;
    };
    bridge = {
      permissions = {
        "*" = "relay";
        "${cfg.serverName}" = "user";
        "@${cfg.admin}:${cfg.serverName}" = "admin";
      };
      personal_filtering_spaces = true; # one "Texts" space
    };
    encryption = {
      allow = true;
      default = true;
      require = false;
      appservice = false; # classic /sync crypto; simplest with Tuwunel
      pickle_key = "$MAUTRIX_GMESSAGES_PICKLE_KEY";
    };
    provisioning.shared_secret = "$MAUTRIX_GMESSAGES_PROVISIONING_SECRET";
    backfill.enabled = true;
    logging = {
      min_level = "info";
      writers = [ { type = "stdout"; format = "json"; } ];
    };
  };
  gmSettingsFile = (pkgs.formats.json { }).generate "mautrix-gmessages-config.json" gmSettings;

  # ---------- mautrix-instagram ----------
  ig = rec {
    # mautrix/meta v0.2611.0 (2026-11-16), Instagram binary only. The flake's
    # nixpkgs-unstable lock has mautrix-meta v0.2605.0. goolm as for gmessages.
    pkg = (pkgs-unstable.mautrix-meta.override { withGoolm = true; }).overrideAttrs (o: rec {
      pname = "mautrix-instagram";
      version = "26.11";
      tag = "v0.2611.0";
      src = pkgs-unstable.fetchFromGitHub {
        owner = "mautrix";
        repo = "meta";
        inherit tag;
        hash = "sha256-cyA8zi+jrOC6SCRXSb2RNmqpZkpVzXShrHnCCoxPwJs=";
      };
      vendorHash = "sha256-sootqoQ0F6TjYnWYbXws2Nu6puCTA31oEtBN8F7lkQ8=";
      subPackages = [ "cmd/mautrix-instagram" ];
      ldflags = [
        "-s"
        "-w"
        "-X"
        "main.Tag=${tag}"
      ];
      meta = o.meta // { mainProgram = "mautrix-instagram"; };
    });
    dataDir = "/var/lib/mautrix-instagram";
    port = 29319;
    config = "${dataDir}/config.yaml";
    registration = "${dataDir}/registration.yaml";
  };
  igSettings = {
    homeserver = gmSettings.homeserver;
    appservice = {
      address = "http://127.0.0.1:${toString ig.port}";
      hostname = "127.0.0.1";
      port = ig.port;
      id = "instagram";
      bot = {
        username = "instagrambot";
        displayname = "Instagram";
      };
      username_template = "instagram_{{.}}";
      as_token = ""; # copied from the generated registration in preStart
      hs_token = "";
    };
    database = {
      type = "sqlite3-fk-wal";
      uri = "file:${ig.dataDir}/instagram.db?_txlock=immediate";
    };
    network = {
      displayname_template = ''{{or .DisplayName .Username "Unknown user"}}'';
    };
    bridge = {
      permissions = gmSettings.bridge.permissions;
      personal_filtering_spaces = true; # one "Instagram" space
    };
    encryption = gmSettings.encryption // {
      pickle_key = "$MAUTRIX_INSTAGRAM_PICKLE_KEY";
    };
    provisioning.shared_secret = "$MAUTRIX_INSTAGRAM_PROVISIONING_SECRET";
    backfill.enabled = true;
    logging = gmSettings.logging;
  };
  igSettingsFile = (pkgs.formats.json { }).generate "mautrix-instagram-config.json" igSettings;

  # ---------- Element Web ----------
  # Palette sampled from comfy.sh/assets/waves.mp4 (deep teal -> fog grey).
  # warning-color is a placeholder warm contrast; tune by eye.
  waves = {
    name = "Waves";
    is_dark = true;
    colors = {
      "accent-color" = "#33786f";
      "primary-color" = "#16685f";
      "warning-color" = "#c96f53";
      "sidebar-color" = "#0f2a28";
      "roomlist-background-color" = "#132f2c";
      "roomlist-text-color" = "#a9bdb8";
      "roomlist-text-secondary-color" = "#768986";
      "roomlist-highlights-color" = "#1e7167";
      "roomlist-separator-color" = "#478278";
      "timeline-background-color" = "#0b1f1d";
      "timeline-text-color" = "#d7e2df";
      "timeline-text-secondary-color" = "#969b99";
      "timeline-highlights-color" = "#16302d";
      "reaction-row-button-selected-bg-color" = "#1e7167";
    };
  };
  elementWeb = pkgs.element-web.override {
    conf = {
      default_server_config."m.homeserver" = {
        base_url = "https://${cfg.publicHost}";
        server_name = cfg.serverName;
      };
      disable_custom_urls = true;
      disable_guests = true;
      show_labs_settings = true;
      setting_defaults = {
        custom_themes = [ waves ];
        theme = "custom-Waves";
      };
    };
  };
in
{
  options.modules.servers.matrix = {
    enable = mkEnableOption "Tuwunel Matrix homeserver (client API only)";
    serverName = mkOption {
      type = types.str;
      example = "comfy.sh";
      description = "Matrix server_name. Permanent: it is part of every user and room ID.";
    };
    publicHost = mkOption {
      type = types.str;
      example = "matrix.comfy.sh";
      description = "Host Caddy serves the client API on.";
    };
    admin = mkOption {
      type = types.str;
      example = "nicholai";
      description = "Localpart that gets admin on the bridges.";
    };
    elementWeb = {
      enable = mkEnableOption "self-hosted Element Web";
      host = mkOption {
        type = types.str;
        default = "chat.${cfg.serverName}";
        defaultText = literalExpression ''"chat.''${serverName}"'';
      };
    };
    gmessages.enable = mkEnableOption "mautrix-gmessages (Google Messages SMS/RCS) bridge";
    instagram.enable = mkEnableOption "mautrix-instagram (Instagram DMs) bridge";
  };

  config = mkIf cfg.enable (mkMerge [
    # ---------------- homeserver ----------------
    {
      warnings =
        optional (!hasRegToken)
          "matrix: ${toString regTokenFile} is missing; Tuwunel registration stays closed."
        ++ optional (cfg.gmessages.enable && !hasGmEnv)
          "matrix: ${toString gmEnvFile} is missing; mautrix-gmessages is not started."
        ++ optional (cfg.instagram.enable && !hasIgEnv)
          "matrix: ${toString igEnvFile} is missing; mautrix-instagram is not started.";

      services.matrix-tuwunel = {
        enable = true;
        settings.global = {
          server_name = cfg.serverName;
          address = [ "127.0.0.1" ];
          port = [ twPort ];
          allow_federation = false;
          trusted_servers = [ ];
          allow_encryption = true;
          allow_registration = hasRegToken;
          new_user_displayname_suffix = "";
          appservice_dir = credDir;
          database_backup_path = "/var/lib/tuwunel/backups";
          database_backups_to_keep = 2;
        } // optionalAttrs hasRegToken {
          registration_token_file = "${credDir}/registration_token";
        };
      };

      systemd.services.tuwunel = {
        requires = optional anyBridge "matrix-appservice-registrations.service";
        after = optional anyBridge "matrix-appservice-registrations.service";
        serviceConfig.LoadCredential =
          optional hasRegToken "registration_token:${config.age.secrets.tuwunel_registration_token.path}"
          ++ optional gmOn "gmessages.yaml:${gm.registration}"
          ++ optional igOn "instagram.yaml:${ig.registration}";
      };

      services.caddy.virtualHosts.${cfg.publicHost}.extraConfig = ''
        # handle blocks: a bare `respond` sorts before reverse_proxy in
        # Caddy's directive order and would answer 404 for everything.
        handle /_matrix/* {
          reverse_proxy 127.0.0.1:${toString twPort}
        }
        handle /_tuwunel/* {
          reverse_proxy 127.0.0.1:${toString twPort}
        }
        handle {
          respond 404
        }
      '';
    }

    (mkIf hasRegToken {
      age.secrets.tuwunel_registration_token = {
        file = regTokenFile;
        mode = "0400"; # root; handed to tuwunel via LoadCredential
      };
    })

    # ---------------- Element Web ----------------
    (mkIf cfg.elementWeb.enable {
      services.caddy.virtualHosts.${cfg.elementWeb.host}.extraConfig = ''
        root * ${elementWeb}
        file_server
        header X-Frame-Options SAMEORIGIN
        header X-Content-Type-Options nosniff
        header Referrer-Policy no-referrer
      '';
    })

    # ---------------- appservice registrations ----------------
    # Generates each bridge's registration once (as_token/hs_token). Runs
    # before tuwunel so LoadCredential always finds the files.
    (mkIf anyBridge {
      systemd.services.matrix-appservice-registrations = {
        description = "Generate Matrix appservice registrations (bridges)";
        wantedBy = [ "multi-user.target" ];
        before = [ "tuwunel.service" ];
        after = [ "systemd-tmpfiles-setup.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          set -eu
          gen() { # <binary> <settings.json> <registration> <user>
            if [ ! -s "$3" ]; then
              tmp=$(mktemp -d)
              install -m 0600 "$2" "$tmp/config.yaml"
              "$1" -g -c "$tmp/config.yaml" -r "$tmp/registration.yaml"
              install -o "$4" -g "$4" -m 0600 "$tmp/registration.yaml" "$3"
              rm -rf "$tmp"
            fi
          }
        '' + optionalString gmOn ''
          gen ${gm.pkg}/bin/mautrix-gmessages ${gmSettingsFile} ${gm.registration} mautrix-gmessages
        '' + optionalString igOn ''
          gen ${ig.pkg}/bin/mautrix-instagram ${igSettingsFile} ${ig.registration} mautrix-instagram
        '';
      };
    })

    # ---------------- mautrix-gmessages ----------------
    (mkIf gmOn {
      users.users.mautrix-gmessages = {
        isSystemUser = true;
        group = "mautrix-gmessages";
        home = gm.dataDir;
      };
      users.groups.mautrix-gmessages = { };

      age.secrets.mautrix_gmessages_env = {
        file = gmEnvFile;
        mode = "0400"; # root; read by systemd for EnvironmentFile
      };

      systemd.tmpfiles.rules = [
        "d ${gm.dataDir} 0700 mautrix-gmessages mautrix-gmessages - -"
      ];

      systemd.services.mautrix-gmessages = {
        description = "mautrix-gmessages (Google Messages SMS/RCS <-> Matrix)";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        requires = [ "tuwunel.service" "matrix-appservice-registrations.service" ];
        after = [ "network-online.target" "tuwunel.service" "matrix-appservice-registrations.service" ];
        path = [ pkgs.ffmpeg-headless ];
        preStart = ''
          set -eu
          umask 0177
          ${pkgs.envsubst}/bin/envsubst -i ${gmSettingsFile} -o ${gm.config}.subst
          ${pkgs.yq}/bin/yq -s '.[0].appservice.as_token = .[1].as_token
            | .[0].appservice.hs_token = .[1].hs_token | .[0]' \
            ${gm.config}.subst ${gm.registration} > ${gm.config}
          rm -f ${gm.config}.subst
        '';
        serviceConfig = {
          User = "mautrix-gmessages";
          Group = "mautrix-gmessages";
          EnvironmentFile = config.age.secrets.mautrix_gmessages_env.path;
          StateDirectory = "mautrix-gmessages";
          StateDirectoryMode = "0700";
          WorkingDirectory = gm.dataDir;
          ExecStart = "${gm.pkg}/bin/mautrix-gmessages -c ${gm.config} -r ${gm.registration}";
          Restart = "on-failure";
          RestartSec = "30s";
          MemoryMax = "512M";
          NoNewPrivileges = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
        };
      };

      # TODO(Nicholai): give grokbot-ene status/restart on tuwunel +
      # mautrix-gmessages? (modules.users.grokbot.agents.ene.sudoCommands in
      # hosts/ene.nix). Left out until he decides.
    })

    # ---------------- mautrix-instagram ----------------
    (mkIf igOn {
      users.users.mautrix-instagram = {
        isSystemUser = true;
        group = "mautrix-instagram";
        home = ig.dataDir;
      };
      users.groups.mautrix-instagram = { };

      age.secrets.mautrix_instagram_env = {
        file = igEnvFile;
        mode = "0400"; # root; read by systemd for EnvironmentFile
      };

      systemd.tmpfiles.rules = [
        "d ${ig.dataDir} 0700 mautrix-instagram mautrix-instagram - -"
      ];

      systemd.services.mautrix-instagram = {
        description = "mautrix-instagram (Instagram DMs <-> Matrix)";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        requires = [ "tuwunel.service" "matrix-appservice-registrations.service" ];
        after = [ "network-online.target" "tuwunel.service" "matrix-appservice-registrations.service" ];
        path = [ pkgs.ffmpeg-headless ];
        preStart = ''
          set -eu
          umask 0177
          ${pkgs.envsubst}/bin/envsubst -i ${igSettingsFile} -o ${ig.config}.subst
          ${pkgs.yq}/bin/yq -s '.[0].appservice.as_token = .[1].as_token
            | .[0].appservice.hs_token = .[1].hs_token | .[0]' \
            ${ig.config}.subst ${ig.registration} > ${ig.config}
          rm -f ${ig.config}.subst
        '';
        serviceConfig = {
          User = "mautrix-instagram";
          Group = "mautrix-instagram";
          EnvironmentFile = config.age.secrets.mautrix_instagram_env.path;
          StateDirectory = "mautrix-instagram";
          StateDirectoryMode = "0700";
          WorkingDirectory = ig.dataDir;
          ExecStart = "${ig.pkg}/bin/mautrix-instagram -c ${ig.config} -r ${ig.registration}";
          Restart = "on-failure";
          RestartSec = "30s";
          MemoryMax = "512M";
          NoNewPrivileges = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
        };
      };
    })

    # TODO(Nicholai): nightly backup to rook/svalbard (restic over tailnet) of
    # /var/lib/tuwunel/backups and a sqlite .backup of gmessages.db. Needs a
    # decision on where the restic repo password lives (new agenix secret?).
  ]);
}

# Proton Mail Bridge on a headless host (rook).
#
# nixpkgs and home-manager both ship services.protonmail-bridge, but those
# units are systemd *user* services WantedBy graphical-session.target. Rook
# has no graphical session, so this module runs a system service as a
# dedicated user instead.
#
# Keychain: pass + a passphrase-free GPG key for that user. secret-service
# / gnome-keyring need a session and a D-Bus bus; they are the wrong fit
# here. The GPG key only wraps Bridge's local vault (session tokens, not
# the Proton account password). Home is mode 0700. See
# docs/rook-proton-bridge.md for the one-time login and how Ene reaches
# the localhost IMAP/SMTP sockets later (SSH tunnel, no open ports).
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.servers.protonmailBridge;
  user = "proton-bridge";
  group = "proton-bridge";
  home = "/var/lib/proton-bridge";
  gpgUserId = "Proton Mail Bridge";
  pkg = cfg.package;
  bridgeBin = getExe pkg;

  proton-bridge-setup = pkgs.writeShellScriptBin "proton-bridge-setup" ''
    set -euo pipefail
    if [ "$(${pkgs.coreutils}/bin/id -u)" -ne 0 ]; then
      echo "run as root: sudo proton-bridge-setup" >&2
      exit 1
    fi

    ${pkgs.coreutils}/bin/install -d -o ${user} -g ${group} -m 0700 ${home} ${home}/.gnupg

    run_as_bridge() {
      ${pkgs.util-linux}/bin/runuser -u ${user} -- env \
        HOME=${home} \
        GNUPGHOME=${home}/.gnupg \
        PASSWORD_STORE_DIR=${home}/.password-store \
        "$@"
    }

    if run_as_bridge ${pkgs.gnupg}/bin/gpg --list-secret-keys --with-colons 2>/dev/null \
         | ${pkgs.gnugrep}/bin/grep -q '^sec:'; then
      echo "proton-bridge-setup: GPG key already present"
    else
      # Passphrase-free so the systemd unit can decrypt the pass store
      # with no pinentry. Protects Bridge's vault only; home is 0700.
      run_as_bridge ${pkgs.gnupg}/bin/gpg --batch --passphrase "" \
        --pinentry-mode loopback \
        --quick-gen-key ${escapeShellArg gpgUserId} default default never
      echo "proton-bridge-setup: created passphrase-free GPG key"
    fi

    if [ -f ${home}/.password-store/.gpg-id ]; then
      echo "proton-bridge-setup: pass store already initialized"
    else
      run_as_bridge ${pkgs.pass}/bin/pass init ${escapeShellArg gpgUserId}
      echo "proton-bridge-setup: initialized pass store"
    fi

    echo "Next: sudo proton-bridge-cli"
    echo "  then, at the >>> prompt: login, then info, then exit"
    echo "  info prints the per-device Bridge password; store it in agenix yourself."
    echo "  See docs/rook-proton-bridge.md"
  '';

  proton-bridge-cli = pkgs.writeShellScriptBin "proton-bridge-cli" ''
    set -euo pipefail
    if [ "$(${pkgs.coreutils}/bin/id -u)" -ne 0 ]; then
      echo "run as root: sudo proton-bridge-cli" >&2
      exit 1
    fi
    if [ ! -t 0 ] || [ ! -t 1 ]; then
      echo "proton-bridge-cli needs a real terminal (the CLI hangs without a tty)." >&2
      echo "From another host: ssh -t rook sudo proton-bridge-cli" >&2
      exit 1
    fi
    if [ ! -f ${home}/.password-store/.gpg-id ]; then
      echo "pass store is not initialized. Run: sudo proton-bridge-setup" >&2
      exit 1
    fi

    # The daemon and the CLI share an exclusive lock. Stop the unit first
    # and always try to start it again on the way out.
    ${pkgs.systemd}/bin/systemctl stop protonmail-bridge.service || true
    trap '${pkgs.systemd}/bin/systemctl start protonmail-bridge.service || true' EXIT

    ${pkgs.util-linux}/bin/runuser -u ${user} -- env \
      HOME=${home} \
      GNUPGHOME=${home}/.gnupg \
      PASSWORD_STORE_DIR=${home}/.password-store \
      ${bridgeBin} --cli "$@"
  '';
in
{
  options.modules.servers.protonmailBridge = {
    enable = mkEnableOption "headless Proton Mail Bridge (localhost IMAP/SMTP)";

    package = mkPackageOption pkgs "protonmail-bridge" { };

    logLevel = mkOption {
      type = types.enum [ "panic" "fatal" "error" "warn" "info" "debug" ];
      default = "info";
      description = "Log level passed to protonmail-bridge --log-level.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !config.services.protonmail-bridge.enable;
        message = ''
          modules.servers.protonmailBridge is the headless system service.
          Disable services.protonmail-bridge (the nixpkgs user unit tied to
          graphical-session.target) on this host.
        '';
      }
    ];

    users.users.${user} = {
      isSystemUser = true;
      inherit group;
      inherit home;
      createHome = true;
      homeMode = "0700";
      description = "Proton Mail Bridge";
    };
    users.groups.${group} = { };

    # pass + gnupg on PATH for the one-time setup/login helpers.
    environment.systemPackages = [
      pkg
      pkgs.pass
      pkgs.gnupg
      proton-bridge-setup
      proton-bridge-cli
    ];

    systemd.services.protonmail-bridge = {
      description = "Proton Mail Bridge (localhost IMAP/SMTP)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      # Stay inactive until proton-bridge-setup has created the pass store.
      unitConfig.ConditionPathExists = "${home}/.password-store/.gpg-id";

      path = [ pkgs.pass pkgs.gnupg ];

      environment = {
        HOME = home;
        GNUPGHOME = "${home}/.gnupg";
        PASSWORD_STORE_DIR = "${home}/.password-store";
      };

      serviceConfig = {
        User = user;
        Group = group;
        WorkingDirectory = home;
        ExecStart = "${bridgeBin} --noninteractive --log-level ${cfg.logLevel}";
        Restart = "always";
        RestartSec = "10s";
        UMask = "0077";
        StateDirectory = "proton-bridge";
        StateDirectoryMode = "0700";
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
        RestrictSUIDSGID = true;
        LockPersonality = true;
        # Outbound HTTPS to Proton, plus IMAP/SMTP on 127.0.0.1 only
        # (Bridge's default host; this module does not patch it).
        # Do not open firewall ports; nothing here listens on tailscale0.
      };
    };
  };
}

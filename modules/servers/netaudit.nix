# netaudit: receive the home router's syslog (dnsmasq DNS/DHCP, conntrack
# events, firewall rejects, nlbwmon exports) on the LAN and keep it on this
# host with retention, plus a daily per-device report.
#
# Privacy: nothing about the network lives in this public repo. The router's
# source address is NOT an option literal here; it is read at firewall start
# from a root-only file on the host (sourcesFile, one IPv4/IPv6 address or
# CIDR per line). Device names come from a private known-devices.json under
# dataDir. Both files are created by hand on the host, never committed.
#
#   sudo install -d -m 700 /etc/netaudit
#   echo '<router LAN address>' | sudo tee /etc/netaudit/allowed-sources
#   sudo chmod 600 /etc/netaudit/allowed-sources
#   sudo systemctl restart firewall        # re-reads the file
#
# Exposure: the listener port is reachable only on `interface` and only from
# the addresses in sourcesFile. It is explicitly refused on every other
# interface (including trusted ones such as tailscale0), and the collector is
# additionally confined to `interface` with RestrictNetworkInterfaces.
#
# Layout under dataDir (0700, user netaudit):
#   {dns,dhcp,conn,fw,bw,inventory,sys}/YYYY-MM-DD.jsonl[.gz]  raw events
#   reports/YYYY-MM-DD.md   daily report      state/seen.json   new-X tracking
#   known-devices.json      optional private {"<mac or ip>": "name"} map
#
# Ad hoc: sudo -u netaudit netaudit-report --since 1h
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.servers.netaudit;

  vectorConfig = pkgs.writeText "netaudit-vector.json" (builtins.toJSON {
    data_dir = "${cfg.dataDir}/.vector";
    timezone = "local";
    sources.router = {
      type = "syslog";
      mode = cfg.protocol;
      address = "${cfg.listenAddress}:${toString cfg.port}";
      max_length = 16384;
    };
    transforms.classify = {
      type = "remap";
      inputs = [ "router" ];
      # Use receive time for file bucketing: the router's syslog clock may not
      # share our time zone. The router's own stamp is kept as router_ts.
      source = ''
        .router_ts = .timestamp
        .timestamp = now()
        app = string(.appname) ?? ""
        msg = string(.message) ?? ""
        .kind = if app == "dnsmasq" {
          "dns"
        } else if app == "dnsmasq-dhcp" {
          "dhcp"
        } else if app == "ctlog" {
          "conn"
        } else if app == "nlbw" {
          "bw"
        } else if app == "leases" || app == "neigh" {
          "inventory"
        } else if app == "kernel" && contains(msg, "IN=") {
          "fw"
        } else {
          "sys"
        }
      '';
    };
    sinks.files = {
      type = "file";
      inputs = [ "classify" ];
      path = "${cfg.dataDir}/{{ kind }}/%Y-%m-%d.jsonl";
      idle_timeout_secs = 60;
      encoding.codec = "json";
    };
  });

  # Fail the build (not the switch) if the generated Vector config is invalid.
  checkedVectorConfig = pkgs.runCommand "netaudit-vector-checked.json" { } ''
    ${pkgs.vector}/bin/vector validate --no-environment ${vectorConfig}
    cp ${vectorConfig} $out
  '';

  reportScript = pkgs.runCommand "netaudit-report.py" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    cp ${./netaudit/netaudit-report.py} $out
    python3 -m py_compile $out
  '';

  netauditReport = pkgs.writeShellApplication {
    name = "netaudit-report";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      export NETAUDIT_ROOT="''${NETAUDIT_ROOT:-${cfg.dataDir}}"
      exec python3 ${reportScript} "$@"
    '';
  };

  netauditPrune = pkgs.writeShellApplication {
    name = "netaudit-prune";
    runtimeInputs = [ pkgs.coreutils pkgs.gzip ];
    text = ''
      root=${escapeShellArg cfg.dataDir}
      yesterday=$(date -d yesterday +%F)
      ${concatStringsSep "\n" (mapAttrsToList (dir: days: ''
        cutoff=$(date -d "-${toString days} days" +%F)
        for f in "$root"/${dir}/*; do
          [ -f "$f" ] || continue
          name=$(basename "$f"); day=''${name:0:10}
          [[ "$day" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || continue
          if [[ "$day" < "$cutoff" ]]; then
            rm -f -- "$f"
          elif [[ "$name" == *.jsonl && "$day" < "$yesterday" ]]; then
            gzip -9 -- "$f"
          fi
        done
      '') cfg.retentionDays)}
    '';
  };

  # Rebuilt on every firewall start: refuse the port off-LAN, then accept it on
  # the LAN interface only from the private allowlist.
  firewallStart = ''
    ip46tables -I nixos-fw 1 -p ${cfg.protocol} --dport ${toString cfg.port} ! -i ${cfg.interface} -j nixos-fw-refuse
    for ipt in iptables ip6tables; do
      $ipt -w -F netaudit-in 2>/dev/null || $ipt -w -N netaudit-in
    done
    netaudit_n=0
    for src in ${escapeShellArgs cfg.allowedSources}; do
      case "$src" in
        *:*) ip6tables -w -A netaudit-in -s "$src" -j nixos-fw-accept ;;
        *) iptables -w -A netaudit-in -s "$src" -j nixos-fw-accept ;;
      esac
      netaudit_n=$((netaudit_n + 1))
    done
    if [ -r ${escapeShellArg cfg.sourcesFile} ]; then
      while read -r src _; do
        case "$src" in
          ""|"#"*) continue ;;
        esac
        if [[ "$src" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}(/[0-9]{1,2})?$ ]]; then
          iptables -w -A netaudit-in -s "$src" -j nixos-fw-accept && netaudit_n=$((netaudit_n + 1))
        elif [[ "$src" =~ ^[0-9a-fA-F:]+(/[0-9]{1,3})?$ ]]; then
          ip6tables -w -A netaudit-in -s "$src" -j nixos-fw-accept && netaudit_n=$((netaudit_n + 1))
        else
          echo "netaudit: ignoring invalid source entry in ${cfg.sourcesFile}" >&2
        fi
      done < ${escapeShellArg cfg.sourcesFile}
    fi
    if [ "$netaudit_n" -eq 0 ]; then
      echo "netaudit: no allowed sources (set ${cfg.sourcesFile}); port ${toString cfg.port} stays closed" >&2
    fi
    ip46tables -A nixos-fw -i ${cfg.interface} -p ${cfg.protocol} --dport ${toString cfg.port} -j netaudit-in
  '';

  firewallStop = ''
    ip46tables -D nixos-fw -i ${cfg.interface} -p ${cfg.protocol} --dport ${toString cfg.port} -j netaudit-in 2>/dev/null || true
    for ipt in iptables ip6tables; do
      $ipt -w -F netaudit-in 2>/dev/null || true
      $ipt -w -X netaudit-in 2>/dev/null || true
    done
  '';
in
{
  options.modules.servers.netaudit = {
    enable = mkEnableOption "router syslog collector and daily per-device network audit report";

    interface = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "LAN interface the router's syslog arrives on. Required: the port is never opened on all interfaces.";
    };

    port = mkOption {
      type = types.port;
      default = 5514;
      description = "Syslog listener port (unprivileged, so the collector needs no capabilities).";
    };

    protocol = mkOption {
      type = types.enum [ "tcp" "udp" ];
      default = "tcp";
      description = "Syslog transport. TCP (OpenWrt log_proto='tcp') does not silently drop bursts.";
    };

    listenAddress = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Bind address. Exposure is controlled by the firewall and RestrictNetworkInterfaces, so a DHCP address change does not break the listener.";
    };

    sourcesFile = mkOption {
      type = types.str;
      default = "/etc/netaudit/allowed-sources";
      description = "Root-only file on the host listing allowed sender addresses/CIDRs, one per line. Kept out of git on purpose. Re-read on firewall start.";
    };

    allowedSources = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Extra allowed sender addresses. Prefer sourcesFile so addresses stay out of public config.";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/netaudit";
      description = "Where raw events, reports and state are stored (mode 0700).";
    };

    retentionDays = mkOption {
      type = types.attrsOf types.ints.positive;
      default = {
        dns = 14;
        conn = 30;
        fw = 30;
        sys = 30;
        dhcp = 365;
        inventory = 365;
        bw = 365;
        reports = 365;
      };
      description = "Days to keep per subdirectory of dataDir (judged by the YYYY-MM-DD file name). Raw files older than yesterday are gzipped.";
    };

    reportTime = mkOption {
      type = types.str;
      default = "*-*-* 00:20:00";
      description = "systemd OnCalendar for pruning plus the report on the previous day.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.interface != null;
        message = "modules.servers.netaudit.interface must be set (LAN NIC only).";
      }
      {
        assertion = !config.networking.nftables.enable;
        message = "modules.servers.netaudit uses networking.firewall.extraCommands (iptables backend).";
      }
    ];

    users.users.netaudit = {
      isSystemUser = true;
      group = "netaudit";
      home = cfg.dataDir;
    };
    users.groups.netaudit = { };

    environment.systemPackages = [ netauditReport ];

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0700 netaudit netaudit -"
      "d ${cfg.dataDir}/.vector 0700 netaudit netaudit -"
      "d ${cfg.dataDir}/state 0700 netaudit netaudit -"
    ] ++ map (dir: "d ${cfg.dataDir}/${dir} 0700 netaudit netaudit -") (attrNames cfg.retentionDays) ++ [
      "d /etc/netaudit 0700 root root -"
    ];

    networking.firewall.extraCommands = firewallStart;
    networking.firewall.extraStopCommands = firewallStop;

    systemd.services.netaudit-collector = {
      description = "netaudit router syslog collector (Vector)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.vector}/bin/vector --config ${checkedVectorConfig}";
        User = "netaudit";
        Group = "netaudit";
        UMask = "0077";
        Restart = "always";
        RestartSec = 5;
        RestrictNetworkInterfaces = cfg.interface;
        ReadWritePaths = [ cfg.dataDir ];
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        NoNewPrivileges = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectHostname = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
        CapabilityBoundingSet = "";
        MemoryMax = "512M";
      };
    };

    systemd.services.netaudit-daily = {
      description = "netaudit retention and daily per-device report";
      after = [ "netaudit-collector.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "netaudit";
        Group = "netaudit";
        UMask = "0077";
        ExecStart = [
          "${netauditPrune}/bin/netaudit-prune"
          "${netauditReport}/bin/netaudit-report"
        ];
        ReadWritePaths = [ cfg.dataDir ];
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        PrivateNetwork = true;
        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
      };
    };

    systemd.timers.netaudit-daily = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.reportTime;
        Persistent = true;
      };
    };
  };
}

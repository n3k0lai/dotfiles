# Ergo IRC server — private IRC for agent mesh + Chatterino
# Tailscale-only access (no public exposure)
#
# After deploy:
#   1. Register accounts via CLI:
#      sudo -u ergochat ergo useradd nicholai -password <pass>
#      (or connect and use /NS REGISTER <password>)
#   2. Configure OpenClaw IRC channel: openclaw configure --section channels
#   3. Connect Chatterino to ene-1.bushbaby-mercat.ts.net:6667 (SASL PLAIN)
#
# Channels:
#   #main    — primary chat (Nicholai + Ene)
#   #agents  — mesh traffic (all agents)
#   #artemis — dev discussion + commit hooks
{ config, pkgs, lib, ... }:

{
  services.ergochat = {
    enable = true;
    settings = {
      network = {
        name = "comfy";
      };

      server = {
        name = "irc.comfy.sh";
        listeners = {
          # Plain IRC — Tailscale encrypts the tunnel
          ":6667" = {};
        };
        max-sendq = "96k";
        ip-cloaking = {
          enabled = true;
          netname = "comfy";
        };
      };

      accounts = {
        registration = {
          enabled = true;
          allow-before-connect = true;
          bcrypt-cost = 12;
        };
        authentication-enabled = true;
        # SASL enforcement disabled — Chatterino's SASL is broken
        # Auth enforced via NickServ + Tailscale network isolation
        require-sasl = {
          enabled = false;
        };
        multiclient = {
          enabled = true;
          allowed-by-default = true;
          # Always-on opt-in: persistent connection acts as bouncer
          always-on = "opt-in";
        };
      };

      channels = {
        default-modes = "+nt";
        registration = {
          enabled = true;
        };
      };

      history = {
        enabled = true;
        channel-length = 2048;
        client-length = 256;
        autoresize-window = "3d";
        persistent = {
          enabled = false;
        };
      };
    };
  };

  # Only allow IRC on Tailscale — invisible from public internet
  networking.firewall.interfaces."tailscale0" = {
    allowedTCPPorts = [ 6667 ];
  };
}

# users/grokbot.nix
# Unprivileged accounts for Grok Bot agents (ene, rook, …). One user per agent
# (grokbot-<name>): no password, no wheel, SSH keys only, sudo limited to an
# explicit command list. Imported by configuration-server.nix; hosts opt in via
# modules.users.grokbot.agents.<name>.
{ config, lib, ... }:

with lib;

let
  agents = config.modules.users.grokbot.agents;
  userName = name: "grokbot-${name}";
in
{
  options.modules.users.grokbot.agents = mkOption {
    default = { };
    description = "Grok Bot agents that get a grokbot-<name> account on this host.";
    type = types.attrsOf (types.submodule {
      options = {
        authorizedKeys = mkOption {
          type = types.listOf types.str;
          description = "SSH public keys allowed to log in as this agent.";
        };
        extraGroups = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Supplementary groups (never wheel).";
        };
        sudoCommands = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Exact commands (absolute path + args) runnable via passwordless sudo.";
        };
      };
    });
  };

  config = mkIf (agents != { }) {
    assertions = mapAttrsToList (name: a: {
      assertion = !(elem "wheel" a.extraGroups);
      message = "grokbot-${name} must not be in wheel.";
    }) agents;

    users.users = mapAttrs' (name: a: nameValuePair (userName name) {
      isNormalUser = true;
      description = "Grok Bot agent (${name})";
      hashedPassword = "!";
      inherit (a) extraGroups;
      openssh.authorizedKeys.keys = a.authorizedKeys;
    }) agents;

    security.sudo.extraRules = mapAttrsToList (name: a: {
      users = [ (userName name) ];
      commands = map (command: { inherit command; options = [ "NOPASSWD" ]; }) a.sudoCommands;
    }) (filterAttrs (_: a: a.sudoCommands != [ ]) agents);
  };
}

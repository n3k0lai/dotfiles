# Fabric Minecraft server module
# Preserves existing data at /opt/minecraft
{ config, pkgs, lib, ... }:

{
  # Minecraft user (matches existing setup)
  users.users.minecraft = {
    isSystemUser = true;
    group = "minecraft";
    home = "/opt/minecraft";
    description = "Minecraft Server";
  };
  users.groups.minecraft = {};

  # Java runtime
  environment.systemPackages = [ pkgs.jdk21 ];

  # Minecraft systemd service (matches current config exactly)
  systemd.services.minecraft = {
    description = "Minecraft Server (Fabric)";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      User = "minecraft";
      Group = "minecraft";
      WorkingDirectory = "/opt/minecraft/server";
      ExecStart = "${pkgs.jdk21}/bin/java -Xmx2G -jar ../fabric-server-launch.jar nogui";
      Restart = "on-failure";
      RestartSec = 30;
      SuccessExitStatus = "0 143";
      KillMode = "control-group";
    };
  };

  # Firewall
  networking.firewall.allowedTCPPorts = [ 25565 ];
}

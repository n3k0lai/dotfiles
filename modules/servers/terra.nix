# My Vanilla Terarria server configuration
{ config, pkgs, ... }:

{
  services.terra = {
    enable = true;
    dataDir = "/home/nicho/games/terraria-server";
    worldName = "MyWorld";
    port = 7777;
    maxPlayers = 8;
    password = "";
    autoStart = true;
    mods = with pkgs; [
      terraria-server-tshock
    ];
  };
}
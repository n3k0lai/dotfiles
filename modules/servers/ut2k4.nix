# My unreal tournament 2004 server configuration
# see https://old.reddit.com/r/unrealtournament/comments/1pdbe69/breaking_unreal_tournament_2004_is_back/
# instagib, low grav, quad jump friendly
{ config, pkgs, ... }:

{
  services.ut2k4 = {
    enable = true;
    dataDir = "/home/nicho/games/ut2k4-server";
    map = "DM-Deck16";
    port = 7777;
    maxPlayers = 16;
    password = "";
    autoStart = true;
    mods = with pkgs; [
      ut2k4-server-official
    ];
  };
}
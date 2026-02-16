# My headless OBS server that functions as a stream bouncer
{ config, pkgs, lib, ... }:

{
  services.obs-server = {
    enable = true;
    streamKey = "my-secret-stream key";
    rtmpUrl = "rtmp://live.twitch.tv/app/";
    autoStart = true;
    mods = with pkgs; [
      obs-studio
    ];
  };
}
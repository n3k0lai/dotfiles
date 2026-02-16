# Fanbulous Outdoor Ceiling Fans with Light for Patios, 20" Weatherproof Plug in Ceiling Fan, Gazebo Fan Remote&APP Control, 3CCT Dimmable,Caged Ceiling Fan with Hanging Hook for Porch, Pergola,Canopy 
# https://www.amazon.com/dp/B0DPHN3K1S
# standardized bluetooth app control fans with an ir controller shimmed by a raspberry pi running home assistant. fans also have warm/cool white ring lights
{ config, pkgs, lib, ... }:

{
  services.fanctl = {
    enable = true;
    fans = [
      {
        name = "patio-fan-1";
        host = ""; # IP address of the fan's bluetooth controller
        mac = "D0:39:72:XX:XX:XX"; # MAC address of the fan's bluetooth controller
        lightEntity = "light.patio_fan_1_light"; # Home Assistant entity ID for the fan's light
        fanEntity = "fan.patio_fan_1"; # Home Assistant entity ID for the fan's fan
      },
      {
        name = "patio-fan-2";
        host = ""; # IP address of the fan's bluetooth controller
        mac = "D0:39:72:YY:YY:YY"; # MAC address of the fan's bluetooth controller
        lightEntity = "light.patio_fan_2_light"; # Home Assistant entity ID for the fan's light
        fanEntity = "fan.patio_fan_2"; # Home Assistant entity ID for the fan's fan
      },
    ];
  };
}
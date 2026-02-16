# My raspberry pi that lives on my patio
# has a security camera, handles my chinese patio fan-lights, and helps home assistant control my patio light accents
{ config, pkgs, ... }:

{
  imports = [
    ../modules/servers/cam.nix,
    ../modules/servers/fans.nix,
  ];
}
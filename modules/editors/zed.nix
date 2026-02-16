# My zed editor configuration
{ config, pkgs, lib, ... }:

{
  programs.zed = {
    enable = true;
    package = pkgs.zed-editor;
  };
}
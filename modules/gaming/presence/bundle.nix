# Packages shared by the NixOS module and the nix-darwin module.
{ pkgs
, wow ? true
, minecraft ? true
}:

let
  tools = [ pkgs.python3 pkgs.coreutils pkgs.grim pkgs.hyprland ];
  watch = pkgs.writeText "presence.py" (builtins.readFile ./watch.py);
  presence = pkgs.writeShellScriptBin "presence" ''
    export PATH=${pkgs.lib.makeBinPath tools}:$PATH
    exec ${pkgs.python3}/bin/python3 ${watch} "$@"
  '';
in {
  inherit presence tools;
  wowPresence = pkgs.writeShellScriptBin "wow-presence" ''
    exec ${presence}/bin/presence "$@"
  '';
  addon = pkgs.runCommand "presence-wow-addon" { } ''
    mkdir -p "$out"
    cp -r ${./addon}/. "$out/"
  '';
  flags = [
    "PRESENCE_WOW=${if wow then "1" else "0"}"
    "PRESENCE_MINECRAFT=${if minecraft then "1" else "0"}"
  ];
}

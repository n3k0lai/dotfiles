# Deploy runtime network labels from the private host inventory.
{ config, lib, privateHosts ? {}, ... }:

with lib;

let
  defaults = import ../private/hosts.example.nix;
  hosts = recursiveUpdate defaults privateHosts;
  net = hosts.network or { };
  kissLabel = net.kissEthernetLabel or "Home LAN";
  macLabels = net.macLabels or { };
  macLines = concatStringsSep "\n" (
    mapAttrsToList (mac: label: "mac ${mac} ${label}") macLabels
  );
in {
  environment.etc."dotfiles/network-labels".text = ''
    kiss_ethernet ${kissLabel}
    ${macLines}
  '';
}

{ config, lib, pkgs, ... }:

with lib;

{
  options.modules.werk = {
    enable = mkEnableOption "work-related applications";
  };

  config = mkIf config.modules.werk.enable {
    # Non-technical work applications only
    # All development tools (VPN, servers, builds, AI agents) are in the work flake
    users.users.nicho.packages = with pkgs; [
      # Communication
      slack
      zoom-us
      
      # Remote access
      freerdp  # Provides sdl-freerdp (used by the `werk` fish function for native Wayland RDP), plus xfreerdp/wlfreerdp
      
      # Security
      yubikey-manager
      yubico-pam
      pcsclite
      pcsc-tools
      
      # VPN (required for work flake)
      openvpn
    ];
  };
}

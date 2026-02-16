{ config, lib, pkgs, ... }:

with lib;

{
  options.modules.work.yubi = {
    enable = mkEnableOption "Yubikey and security tools";
  };

  config = mkIf config.modules.work.yubi.enable {
    users.users.nicho.packages = with pkgs; [
      yubikey-manager
      yubico-pam
      pcsclite
      pcsc-tools
    ];
  };
}

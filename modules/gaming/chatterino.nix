{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.gaming.chatterino;
in {
  options.modules.gaming.chatterino = {
    enable = mkEnableOption "Chatterino with streamlink integration";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      chatterino2
      streamlink  # Use pipx to install the latest version
      #pipx  # Used to install latest streamlink
      mpv  # Required for streamlink
      git  # Required for cloning settings
      openssh  # Required for git SSH access
    ];

    # Clone settings for each real user
    system.activationScripts.chatterinoSettings = lib.stringAfter [ "users" ] ''
      for user_home in /home/*; do
        # Skip if not a directory or is lost+found
        if [ ! -d "$user_home" ] || [ "$(basename "$user_home")" = "lost+found" ]; then
          continue
        fi
        
        user=$(basename "$user_home")
        
        # Check if user exists in /etc/passwd
        if ! ${pkgs.coreutils}/bin/id -u "$user" >/dev/null 2>&1; then
          continue
        fi
        
        settings_dir="$user_home/.local/share/chatterino/Settings"
        
        # Run as the actual user
        ${pkgs.sudo}/bin/sudo -u "$user" ${pkgs.bash}/bin/bash <<EOF
          settings_dir="$settings_dir"
          mkdir -p "\$settings_dir"
          
          # Configure git safe directory
          ${pkgs.git}/bin/git config --global --add safe.directory "\$settings_dir" 2>/dev/null || true
          
          # Clone or pull settings
          if [ ! -d "\$settings_dir/.git" ]; then
            if ${pkgs.git}/bin/git clone git@github.com:n3k0lai/my-chatterino-settings.git "\$settings_dir.tmp" 2>/dev/null; then
              cp -r "\$settings_dir.tmp"/. "\$settings_dir/"
              rm -rf "\$settings_dir.tmp"
            fi
          else
            cd "\$settings_dir"
            ${pkgs.git}/bin/git pull origin master 2>/dev/null || true
          fi
      EOF
      done
    '';

    # Install latest streamlink via pipx for each user
    # Run: pipx install streamlink (or pipx upgrade streamlink)
  };
}

let
  # ===========================================
  # HOST KEYS - add new hosts here
  # ===========================================
  kiss = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ5xQ12AZjr/B7nwR4xQwtnh7g/4PlBMoiZ3MsTLoInK root@tr1ste";
  ene = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDJVEWuJ9zhai0WJm3j90jOps4KIOiG8JITvoOcJ4hrA root@test";
  # blade = "ssh-ed25519 AAAA...";  # future host example

  # ===========================================
  # USER KEY - for editing secrets from any machine
  # ===========================================
  nicho = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ3pJ8BVreaSwvtQd7Ytayg+qrzm3JkhAPfd7YIM/3r2";

  # ===========================================
  # HOST GROUPS - organize by access level
  # ===========================================
  allHosts = [ kiss ene ];
  desktops = [ kiss ];           # desktop machines only
  servers = [ ene ];             # server machines only

in
{
  # ===========================================
  # DESKTOP-ONLY SECRETS (kiss)
  # ===========================================
  "modules/core/config/secrets/id_ed25519.age".publicKeys = desktops ++ [ nicho ];
  "modules/core/config/secrets/ssh_config.age".publicKeys = desktops ++ [ nicho ];
  "modules/core/config/secrets/work_creds.age".publicKeys = desktops ++ [ nicho ];
  "modules/core/config/secrets/user_password.age".publicKeys = desktops ++ [ nicho ];

  # ===========================================
  # SHARED SECRETS (all hosts that need them)
  # ===========================================
  "modules/core/config/secrets/garmin_email.age".publicKeys = allHosts ++ [ nicho ];
  "modules/core/config/secrets/garmin_password.age".publicKeys = allHosts ++ [ nicho ];
  "modules/core/config/secrets/gdrive_credentials.age".publicKeys = allHosts ++ [ nicho ];
  "modules/core/config/secrets/gdrive_token.age".publicKeys = allHosts ++ [ nicho ];

  # ===========================================
  # SERVER SECRETS (ene)
  # ===========================================
  "modules/servers/secrets/xai_api_key.age".publicKeys = servers ++ [ nicho ];
}

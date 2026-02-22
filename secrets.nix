let
  # ===========================================
  # HOST KEYS - add new hosts here
  # ===========================================
  kiss = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ5xQ12AZjr/B7nwR4xQwtnh7g/4PlBMoiZ3MsTLoInK root@tr1ste";
  ene = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDJVEWuJ9zhai0WJm3j90jOps4KIOiG8JITvoOcJ4hrA root@test";
  chat = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKc43hg3+7eZ8JUTNNi+F0k2fjs8nVusG8wcLCj8Xc4A root@chateau";

  # ===========================================
  # USER KEY - for editing secrets from any machine
  # ===========================================
  nicho = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ3pJ8BVreaSwvtQd7Ytayg+qrzm3JkhAPfd7YIM/3r2";

  # ===========================================
  # HOST GROUPS - organize by access level
  # ===========================================
  allHosts = [ kiss ene chat ];
  desktops = [ kiss ];           # desktop machines only
  servers = [ ene chat ];        # server machines only
  streaming = [ chat ];          # stream bouncer

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

  # ===========================================
  # STREAMING SECRETS (chat — stream bouncer)
  # ===========================================
  "modules/servers/secrets/twitch_stream_key.age".publicKeys = streaming ++ [ nicho ];
  "modules/servers/secrets/x_stream_key.age".publicKeys = streaming ++ [ nicho ];

  # ===========================================
  # MESH DB SECRETS (agent → Postgres on Chat)
  # ===========================================
  # Ene's read-only credentials (decrypted on ene)
  "modules/servers/secrets/ene_pg_finance_reader.age".publicKeys = [ ene nicho ];
  "modules/servers/secrets/ene_pg_personal_reader.age".publicKeys = [ ene nicho ];
  # Chat's Postgres role passwords (decrypted on chat, applied via activation script)
  "modules/servers/secrets/pg_mesh_password.age".publicKeys = [ chat nicho ];
  "modules/servers/secrets/pg_mesh_reader_password.age".publicKeys = [ chat nicho ];
  "modules/servers/secrets/pg_finance_admin_password.age".publicKeys = [ chat nicho ];
  "modules/servers/secrets/pg_personal_admin_password.age".publicKeys = [ chat nicho ];
  "modules/servers/secrets/pg_work_admin_password.age".publicKeys = [ chat nicho ];
}

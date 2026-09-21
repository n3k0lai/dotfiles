# Honcho memory server for Hermes (Ene + Rook share one instance).
#
# Official stack is the published image, not a from-source build:
#   API + deriver + Postgres/pgvector + Redis.
# Docs: https://honcho.dev/docs/v3/contributing/self-hosting
#
# Tailscale only. Docker publishes the API to 127.0.0.1. Caddy is the
# tailnet listener so Docker's iptables do not punch the host firewall.
# Postgres and Redis stay on the compose network. Do not publish them:
# Rook already owns host port 5432.
#
# Gate before enable = true:
#   1. agenix the raw xAI API key (one line, no Discord paste)
#   2. Probe embedding dimensions and set embeddingDimensions.
#      Honcho pins pgvector width at first migration. A mismatch refuses boot
#      and a wrong first boot is painful to undo.
#   3. rook switch, then point both Hermes homes at the Caddy URL.
#
# Text features use grok-4.3, not grok-4.7. The deriver runs on every turn.
# Dream is off until the stack has soaked. SuperGrok OAuth does not feed this.
{ config, lib, pkgs, ... }:
let
  cfg = config.modules.servers.honcho;
  stateDir = "/var/lib/honcho";
  initSql = pkgs.writeText "honcho-init.sql" ''
    CREATE EXTENSION IF NOT EXISTS vector;
  '';
  composeFile = pkgs.writeText "honcho-compose.yml" ''
    name: honcho
    services:
      api:
        image: ${cfg.image}
        entrypoint: ["sh", "docker/entrypoint.sh"]
        depends_on:
          database:
            condition: service_healthy
          redis:
            condition: service_healthy
        ports:
          - "127.0.0.1:${toString cfg.apiBindPort}:8000"
        environment:
          DB_CONNECTION_URI: postgresql+psycopg://postgres:''${HONCHO_DB_PASSWORD}@database:5432/postgres
          CACHE_URL: redis://redis:6379/0?suppress=true
          CACHE_ENABLED: "true"
          AUTH_USE_AUTH: "false"
          LOG_LEVEL: INFO
          DREAM_ENABLED: "false"
          LLM_OPENAI_API_KEY: ''${XAI_API_KEY}
          DERIVER_MODEL_CONFIG__TRANSPORT: openai
          DERIVER_MODEL_CONFIG__MODEL: ${cfg.textModel}
          DERIVER_MODEL_CONFIG__OVERRIDES__BASE_URL: https://api.x.ai/v1
          DERIVER_MODEL_CONFIG__STRUCTURED_OUTPUT_MODE: json_object
          SUMMARY_MODEL_CONFIG__TRANSPORT: openai
          SUMMARY_MODEL_CONFIG__MODEL: ${cfg.textModel}
          SUMMARY_MODEL_CONFIG__OVERRIDES__BASE_URL: https://api.x.ai/v1
          DIALECTIC_LEVELS__minimal__MODEL_CONFIG__TRANSPORT: openai
          DIALECTIC_LEVELS__minimal__MODEL_CONFIG__MODEL: ${cfg.textModel}
          DIALECTIC_LEVELS__minimal__MODEL_CONFIG__OVERRIDES__BASE_URL: https://api.x.ai/v1
          DIALECTIC_LEVELS__low__MODEL_CONFIG__TRANSPORT: openai
          DIALECTIC_LEVELS__low__MODEL_CONFIG__MODEL: ${cfg.textModel}
          DIALECTIC_LEVELS__low__MODEL_CONFIG__OVERRIDES__BASE_URL: https://api.x.ai/v1
          DIALECTIC_LEVELS__medium__MODEL_CONFIG__TRANSPORT: openai
          DIALECTIC_LEVELS__medium__MODEL_CONFIG__MODEL: ${cfg.textModel}
          DIALECTIC_LEVELS__medium__MODEL_CONFIG__OVERRIDES__BASE_URL: https://api.x.ai/v1
          DIALECTIC_LEVELS__high__MODEL_CONFIG__TRANSPORT: openai
          DIALECTIC_LEVELS__high__MODEL_CONFIG__MODEL: ${cfg.textModel}
          DIALECTIC_LEVELS__high__MODEL_CONFIG__OVERRIDES__BASE_URL: https://api.x.ai/v1
          DIALECTIC_LEVELS__max__MODEL_CONFIG__TRANSPORT: openai
          DIALECTIC_LEVELS__max__MODEL_CONFIG__MODEL: ${cfg.textModel}
          DIALECTIC_LEVELS__max__MODEL_CONFIG__OVERRIDES__BASE_URL: https://api.x.ai/v1
          EMBEDDING_VECTOR_DIMENSIONS: "${if cfg.embeddingDimensions == null then "unset" else toString cfg.embeddingDimensions}"
          EMBEDDING_MODEL_CONFIG__TRANSPORT: openai
          EMBEDDING_MODEL_CONFIG__MODEL: ${cfg.embeddingModel}
          EMBEDDING_MODEL_CONFIG__OVERRIDES__BASE_URL: https://api.x.ai/v1
          EMBEDDING_MODEL_CONFIG__OVERRIDES__API_KEY_ENV: LLM_OPENAI_API_KEY
        restart: unless-stopped

      deriver:
        image: ${cfg.image}
        entrypoint: ["/app/.venv/bin/python", "-m", "src.deriver"]
        depends_on:
          api:
            condition: service_healthy
          database:
            condition: service_healthy
          redis:
            condition: service_healthy
        environment:
          DB_CONNECTION_URI: postgresql+psycopg://postgres:''${HONCHO_DB_PASSWORD}@database:5432/postgres
          CACHE_URL: redis://redis:6379/0?suppress=true
          CACHE_ENABLED: "true"
          AUTH_USE_AUTH: "false"
          LOG_LEVEL: INFO
          DREAM_ENABLED: "false"
          LLM_OPENAI_API_KEY: ''${XAI_API_KEY}
          DERIVER_MODEL_CONFIG__TRANSPORT: openai
          DERIVER_MODEL_CONFIG__MODEL: ${cfg.textModel}
          DERIVER_MODEL_CONFIG__OVERRIDES__BASE_URL: https://api.x.ai/v1
          DERIVER_MODEL_CONFIG__STRUCTURED_OUTPUT_MODE: json_object
          SUMMARY_MODEL_CONFIG__TRANSPORT: openai
          SUMMARY_MODEL_CONFIG__MODEL: ${cfg.textModel}
          SUMMARY_MODEL_CONFIG__OVERRIDES__BASE_URL: https://api.x.ai/v1
          EMBEDDING_VECTOR_DIMENSIONS: "${if cfg.embeddingDimensions == null then "unset" else toString cfg.embeddingDimensions}"
          EMBEDDING_MODEL_CONFIG__TRANSPORT: openai
          EMBEDDING_MODEL_CONFIG__MODEL: ${cfg.embeddingModel}
          EMBEDDING_MODEL_CONFIG__OVERRIDES__BASE_URL: https://api.x.ai/v1
          EMBEDDING_MODEL_CONFIG__OVERRIDES__API_KEY_ENV: LLM_OPENAI_API_KEY
        restart: unless-stopped

      database:
        image: pgvector/pgvector:pg15
        restart: unless-stopped
        command: ["postgres", "-c", "max_connections=200"]
        environment:
          POSTGRES_DB: postgres
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: ''${HONCHO_DB_PASSWORD}
          PGDATA: /var/lib/postgresql/data/pgdata
        volumes:
          - ${initSql}:/docker-entrypoint-initdb.d/init.sql:ro
          - pgdata:/var/lib/postgresql/data
        healthcheck:
          test: ["CMD-SHELL", "pg_isready -U postgres -d postgres"]
          interval: 5s
          timeout: 5s
          retries: 5

      redis:
        image: redis:8.2
        restart: unless-stopped
        volumes:
          - redis-data:/data
        healthcheck:
          test: ["CMD-SHELL", "redis-cli ping"]
          interval: 5s
          timeout: 5s
          retries: 5

    volumes:
      pgdata:
      redis-data:
  '';
in
{
  options.modules.servers.honcho = {
    enable = lib.mkEnableOption "Honcho memory server (Tailscale, Docker)";

    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/plastic-labs/honcho:latest";
      description = "Published Honcho image. Pin a digest after the first good pull.";
    };

    textModel = lib.mkOption {
      type = lib.types.str;
      default = "grok-4.3";
      description = "xAI model for deriver, summary, and dialectic. Not the Hermes chat model.";
    };

    embeddingModel = lib.mkOption {
      type = lib.types.str;
      default = "v1";
      description = "xAI embedding model id from GET /v1/embedding-models.";
    };

    embeddingDimensions = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      description = "Vector width. Required before enable. Must match the embedding model. Immutable after first migration.";
    };

    apiKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/agenix/honcho_xai_api_key";
      description = "Raw xAI API key, one line, no prefix. Not SuperGrok OAuth.";
    };

    apiBindPort = lib.mkOption {
      type = lib.types.port;
      default = 18000;
      description = "Localhost port Docker publishes. Caddy is the tailnet front.";
    };

    tailnetPort = lib.mkOption {
      type = lib.types.port;
      default = 18791;
      description = "Port Caddy listens on. Reachable via tailscale0 only.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.embeddingDimensions != null;
        message = "modules.servers.honcho.embeddingDimensions must be set before enable. Probe xAI /v1/embeddings and use that width. First migration pins it.";
      }
    ];

    age.secrets.honcho_xai_api_key = {
      file = ./secrets/honcho_xai_api_key.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };

    virtualisation.docker.enable = true;

    users.users.nicho.extraGroups = lib.mkAfter [ "docker" ];

    services.caddy.virtualHosts.":${toString cfg.tailnetPort}" = {
      extraConfig = ''
        reverse_proxy 127.0.0.1:${toString cfg.apiBindPort}
      '';
    };

    systemd.services.honcho = {
      description = "Honcho memory stack (API, deriver, pgvector, Redis)";
      after = [ "docker.service" "network-online.target" "agenix.service" ];
      requires = [ "docker.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.docker pkgs.docker-compose pkgs.coreutils pkgs.gnused pkgs.openssl ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = 600;
      };
      script = ''
        set -euo pipefail
        install -d -m 0700 ${stateDir}
        if [ ! -s ${stateDir}/db-password ]; then
          openssl rand -hex 16 > ${stateDir}/db-password
          chmod 0400 ${stateDir}/db-password
        fi
        key=$(tr -d '\n' < ${cfg.apiKeyFile})
        if [ -z "$key" ]; then
          echo "honcho: empty API key at ${cfg.apiKeyFile}" >&2
          exit 1
        fi
        umask 077
        cat > ${stateDir}/honcho.env <<EOF
        HONCHO_DB_PASSWORD=$(cat ${stateDir}/db-password)
        XAI_API_KEY=$key
        EOF
        # The heredoc above keeps leading spaces. Strip them.
        sed -i 's/^[[:space:]]*//' ${stateDir}/honcho.env
        chmod 0400 ${stateDir}/honcho.env
        docker compose --env-file ${stateDir}/honcho.env -f ${composeFile} up -d
      '';
      preStop = ''
        if [ -f ${stateDir}/honcho.env ]; then
          docker compose --env-file ${stateDir}/honcho.env -f ${composeFile} down
        fi
      '';
    };
  };
}

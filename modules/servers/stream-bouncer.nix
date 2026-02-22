# Stream Bouncer — headless RTMP relay with fallback scene
#
# Architecture:
#   Kiss (gaming PC) → SRT/RTMP → nginx-rtmp (Chat) → Twitch/YouTube
#   If Kiss drops, ffmpeg switches to a fallback scene:
#     - Headless Chromium rendering chat overlay (chatis.is2511.com)
#     - Looping Twitch clips / BRB screen
#     - Encoded via Intel HD 530 VAAPI (hardware, ~15W)
#
# No OBS needed — nginx-rtmp handles ingest, ffmpeg handles compositing.
# IRL Toolkit-style resilience without the cloud middleman.
#
{ config, pkgs, lib, ... }:

let
  cfg = config.services.stream-bouncer;

  # Fallback scene compositor script
  fallbackScript = pkgs.writeShellScript "stream-fallback" ''
    export PATH="${lib.makeBinPath (with pkgs; [ ffmpeg-full chromium coreutils gnugrep gnused curl ])}:$PATH"

    CHAT_URL="''${CHAT_OVERLAY_URL:-https://chatis.is2511.com/}"
    CLIPS_DIR="''${CLIPS_DIR:-${cfg.clipsDir}}"
    STREAM_KEY=$(cat ${cfg.streamKeyFile})
    RTMP_OUT="''${RTMP_OUTPUT:-${cfg.rtmpOutput}/$STREAM_KEY}"
    RESOLUTION="''${RESOLUTION:-1920x1080}"
    FPS="''${FPS:-30}"
    VAAPI_DEVICE="''${VAAPI_DEVICE:-/dev/dri/renderD128}"

    # Build clip loop playlist if clips exist
    CLIP_INPUT=""
    if [ -d "$CLIPS_DIR" ] && ls "$CLIPS_DIR"/*.mp4 &>/dev/null; then
      PLAYLIST="/tmp/clips_playlist.txt"
      : > "$PLAYLIST"
      for f in "$CLIPS_DIR"/*.mp4; do
        echo "file '$f'" >> "$PLAYLIST"
      done
      CLIP_INPUT="-f concat -safe 0 -stream_loop -1 -i $PLAYLIST"
    fi

    # Fallback: clips (looping) + chat overlay via browser capture
    # If no clips, show a static BRB image or solid color
    if [ -n "$CLIP_INPUT" ]; then
      # Clips + chat overlay composited
      exec ffmpeg -y \
        -vaapi_device "$VAAPI_DEVICE" \
        $CLIP_INPUT \
        -f x11grab -framerate "$FPS" -video_size "$RESOLUTION" -i :99 \
        -filter_complex "[0:v]scale=$RESOLUTION,format=nv12,hwupload[bg];[1:v]format=nv12,hwupload[fg];[bg][fg]overlay_vaapi" \
        -c:v h264_vaapi -b:v 4500k -maxrate 5000k -bufsize 10000k \
        -g $((FPS * 2)) -r "$FPS" \
        -c:a aac -b:a 160k -ar 44100 \
        -f flv "$RTMP_OUT"
    else
      # No clips — just the chat overlay on black background
      exec ffmpeg -y \
        -vaapi_device "$VAAPI_DEVICE" \
        -f x11grab -framerate "$FPS" -video_size "$RESOLUTION" -i :99 \
        -vf 'format=nv12,hwupload' \
        -c:v h264_vaapi -b:v 4500k -maxrate 5000k -bufsize 10000k \
        -g $((FPS * 2)) -r "$FPS" \
        -c:a aac -b:a 160k -ar 44100 \
        -f flv "$RTMP_OUT"
    fi
  '';

  # Watchdog script — detects Kiss dropout and triggers fallback
  watchdogScript = pkgs.writeShellScript "stream-watchdog" ''
    export PATH="${lib.makeBinPath (with pkgs; [ coreutils gnugrep curl ])}:$PATH"

    RTMP_STAT="http://127.0.0.1:${toString cfg.rtmpStatPort}/stat"
    CHECK_INTERVAL="''${CHECK_INTERVAL:-3}"
    FALLBACK_PID=""
    KISS_STREAM="''${KISS_STREAM_NAME:-kiss}"
    STATE="relay"  # relay | fallback

    cleanup() {
      [ -n "$FALLBACK_PID" ] && kill "$FALLBACK_PID" 2>/dev/null
      exit 0
    }
    trap cleanup SIGTERM SIGINT

    echo "[watchdog] Monitoring stream from Kiss..."

    while true; do
      # Check if Kiss is publishing to nginx-rtmp
      KISS_LIVE=$(curl -s "$RTMP_STAT" | grep -c "<name>$KISS_STREAM</name>" 2>/dev/null || echo "0")

      if [ "$KISS_LIVE" -gt 0 ] && [ "$STATE" = "fallback" ]; then
        echo "[watchdog] Kiss reconnected — switching back to relay"
        [ -n "$FALLBACK_PID" ] && kill "$FALLBACK_PID" 2>/dev/null
        FALLBACK_PID=""
        STATE="relay"

      elif [ "$KISS_LIVE" -eq 0 ] && [ "$STATE" = "relay" ]; then
        echo "[watchdog] Kiss dropped — switching to fallback scene"
        ${fallbackScript} &
        FALLBACK_PID=$!
        STATE="fallback"
      fi

      sleep "$CHECK_INTERVAL"
    done
  '';

  # Push script — reads stream keys from agenix files at runtime
  pushScript = pkgs.writeShellScript "stream-push" ''
    export PATH="${lib.makeBinPath [ pkgs.ffmpeg-full pkgs.coreutils ]}:$PATH"
    TWITCH_KEY=$(cat ${cfg.streamKeyFile})
    ffmpeg -i "rtmp://127.0.0.1:${toString cfg.rtmpPort}/internal/$1" \
      -c copy -f flv "${cfg.rtmpOutput}/$TWITCH_KEY" \
      ${lib.optionalString cfg.enableX ''
      -c copy -f flv "rtmp://a.rtmp.youtube.com/live2/$(cat ${cfg.xStreamKeyFile})"
      ''} \
      2>/dev/null &
  '';

  # nginx-rtmp config
  rtmpConfig = ''
    worker_processes 1;
    events { worker_connections 1024; }

    rtmp {
      server {
        listen ${toString cfg.rtmpPort};
        chunk_size 4096;

        # Ingest from Kiss (or phone for IRL)
        application ingest {
          live on;
          record off;

          # Push to internal app, which triggers the push script
          push rtmp://127.0.0.1:${toString cfg.rtmpPort}/internal;
        }

        # Internal app — relays to Twitch/X via exec_push
        application internal {
          live on;
          record off;
          exec_push ${pushScript} $name;
        }
      }
    }

    http {
      server {
        listen ${toString cfg.rtmpStatPort};
        location /stat {
          rtmp_stat all;
          rtmp_stat_stylesheet stat.xsl;
        }
      }
    }
  '';
in
{
  options.services.stream-bouncer = {
    enable = lib.mkEnableOption "headless stream bouncer with fallback scene";

    rtmpPort = lib.mkOption {
      type = lib.types.port;
      default = 1935;
      description = "RTMP ingest port";
    };

    rtmpStatPort = lib.mkOption {
      type = lib.types.port;
      default = 8085;
      description = "RTMP stats HTTP port";
    };

    hookPort = lib.mkOption {
      type = lib.types.port;
      default = 8086;
      description = "Webhook port for publish events";
    };

    rtmpOutput = lib.mkOption {
      type = lib.types.str;
      default = "rtmp://live.twitch.tv/app";
      description = "RTMP output URL (without stream key)";
    };

    streamKeyFile = lib.mkOption {
      type = lib.types.str;
      default = config.age.secrets.twitch_stream_key.path;
      description = "Path to file containing Twitch stream key (agenix)";
    };

    xStreamKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Path to file containing X/Twitter stream key (agenix)";
    };

    enableX = lib.mkEnableOption "simultaneous X/Twitter live streaming";

    clipsDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/stream-bouncer/clips";
      description = "Directory for looping fallback clips";
    };

    chatOverlayUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://chatis.is2511.com/";
      description = "Chat overlay URL for fallback scene";
    };
  };

  config = lib.mkIf cfg.enable {
    # Required packages
    environment.systemPackages = with pkgs; [
      ffmpeg-full          # Compositing + VAAPI encoding
      chromium             # Headless browser for chat overlay
      intel-media-driver   # VAAPI driver for HD 530
      libva                # VA-API runtime
      libva-utils          # vainfo diagnostic
      xorg.xorgserver      # Xvfb for headless rendering
    ];

    # Intel VAAPI
    hardware.graphics = {
      enable = true;
      extraPackages = with pkgs; [
        intel-media-driver
        libva
      ];
    };

    # Xvfb — virtual display for Chromium browser capture
    systemd.services.stream-xvfb = {
      description = "Virtual framebuffer for stream bouncer";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.xorg.xorgserver}/bin/Xvfb :99 -screen 0 1920x1080x24 -ac";
        Restart = "always";
        Type = "simple";
      };
    };

    # Chromium rendering chat overlay on Xvfb
    systemd.services.stream-chat-overlay = {
      description = "Chat overlay browser for fallback scene";
      after = [ "stream-xvfb.service" ];
      requires = [ "stream-xvfb.service" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        DISPLAY = ":99";
      };
      serviceConfig = {
        ExecStart = "${pkgs.chromium}/bin/chromium --no-sandbox --disable-gpu --kiosk --window-size=1920,1080 --window-position=0,0 ${cfg.chatOverlayUrl}";
        Restart = "always";
        User = "stream-bouncer";
        Group = "stream-bouncer";
      };
    };

    # nginx-rtmp ingest server
    systemd.services.stream-rtmp = {
      description = "RTMP ingest server (nginx-rtmp)";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.nginxMainline.override { modules = [ pkgs.nginxModules.rtmp ]; }}/bin/nginx -c ${pkgs.writeText "nginx-rtmp.conf" rtmpConfig} -g 'daemon off;'";
        Restart = "always";
        Type = "simple";
      };
    };

    # Watchdog — monitors Kiss and triggers fallback
    systemd.services.stream-watchdog = {
      description = "Stream bouncer watchdog";
      after = [ "stream-rtmp.service" "stream-xvfb.service" "stream-chat-overlay.service" ];
      requires = [ "stream-rtmp.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${watchdogScript}";
        Restart = "always";
        User = "stream-bouncer";
        Group = "stream-bouncer";
      };
    };

    # Service user
    users.users.stream-bouncer = {
      isSystemUser = true;
      group = "stream-bouncer";
      home = "/var/lib/stream-bouncer";
      createHome = true;
      extraGroups = [ "video" "render" ];  # VAAPI access
    };
    users.groups.stream-bouncer = {};

    # Firewall — allow RTMP ingest over Tailscale
    networking.firewall.allowedTCPPorts = [
      cfg.rtmpPort
      cfg.rtmpStatPort
    ];
  };
}

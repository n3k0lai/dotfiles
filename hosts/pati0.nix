# pati0 — patio Raspberry Pi 4 edge node for Rook's Home Assistant
#
# Role: NOT a second HA brain. Rook = primary HA + Matter + MQTT.
# pati0 handles:
#   - Pi CSI camera → still/stream toward rook HA
#   - patio fan-lights (BT/IR shim) → MQTT entities on rook
#   - optional meshtastic later (module not imported until hash filled)
#
# Network: LAN 192.168.68.60 (DHCP) · MAC dc:a6:32:5b:69:28 · Tailscale TBD
# MQTT / HA: rook Tailscale 100.114.138.5
#
# Build / switch ON the Pi (aarch64):
#   sudo nixos-rebuild switch --flake /path/to/dotfiles#pati0
# Cross-eval from rook/kiss is OK; full build needs aarch64 or binfmt.
{ config, pkgs, lib, ... }:

let
  rookTs = "100.114.138.5";
  rookMqttHost = rookTs;
  rookHaUrl = "http://${rookTs}:8123";

  # SSH keys that already work on the stock image (hermes@rook + nicholai).
  sshKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJntuxxz6/6FmMQyOxIDTF36Ql4ZDfZymAtPTGAGqmFO"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE4uva6ZuYgjkbSvjVwu1t9A0hReGWmwmoIpbCKxDfP/ nicholai@comfy.sh"
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDYabFqlObrdCGfwz4kFCcKXEpWVPtG6qMrUD5cxH6+/tIZJjMGnRyYm/rbScbz0Zzy0w8CKtBFuJkAm3mTVfczl8O80mIEXnV8Ue1reSastDiI/DMhUKmqtPruIEd1EBtsBkY49tmUl6zM1yfwqSZl+ecS0E4F7qt26wpIbMTaP8db+38s7OmTOvRMqe+TgaTUvGR51xTORIuOWgw6bJZgbm8sALwi2KdMwXAbUb/yK8KMdaThavanxsQkj2C0ORB/4toj1hBqk2umDlFx6GqGIFxcUmMkaCYGmXbHVFLsnTUgk0Uf1B4/fqfzmFygZ4LU1CRVTYHBIrf2+7BCj18tozf9t6ebq1A4JCkC0UkGZ+q2Yv0++JVkjgphdyE9u8nTeWl0EgQM4F8qcTPRePv3nOqLrQu9T+OMDLUTlDIc0cRLDAffrDkn/UNL4QG4rFJlbV5Bgtyg21JPelO5LEH2ph2V19T785PUxxXE72uMCYvGNzoDj5JLJv+MGSkH8gS8TPy+Ret5FkyeEtWtX+iMRCuhf8MCUwW2/qslwBRRqxioDyNHhN4t74B8XH+oJWGI0bnC+R/P5b5U0YVqy2zePKjt393/HKMlzCYwD9nN/1akoN6PsjjaYl93VMVm07K0Qryh9TxEaGuH1TCdFjcKyAvoLs+/ParxSy20PZSY3Q== rook@comfy.sh"
  ];

  # Camera Module v2 (IMX219) is the default guess — change if yours is v1/v3.
  # v1 = ov5647 · v2 = imx219 · v3 = imx708
  cameraOverlay = "imx219";

  fans = [
    {
      name = "patio-fan-1";
      mac = "D0:39:72:XX:XX:XX"; # replace after first BT scan
      lightEntity = "light.patio_fan_1_light";
      fanEntity = "fan.patio_fan_1";
    }
    {
      name = "patio-fan-2";
      mac = "D0:39:72:YY:YY:YY";
      lightEntity = "light.patio_fan_2_light";
      fanEntity = "fan.patio_fan_2";
    }
  ];
in
{
  networking.hostName = "pati0";
  networking.domain = "lan";

  # --- boot: RPi vendor kernel so CSI overlays / camera_auto_detect work ---
  # Stock sd-card image used mainline + u-boot FDTDIR; CSI stayed disabled.
  boot.kernelPackages = pkgs.linuxPackages_rpi4;
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;
  boot.consoleLogLevel = lib.mkDefault 7;

  # Write camera lines into the firmware config that the Pi GPU bootloader reads.
  # generic-extlinux still boots the NixOS kernel; start.elf applies overlays first.
  system.activationScripts.pati0FirmwareCamera = {
    deps = [ ];
    text = ''
      CFG=/boot/firmware/config.txt
      if [ -f "$CFG" ]; then
        if ! grep -q 'pati0-camera' "$CFG" 2>/dev/null; then
          printf '\n# pati0-camera (managed by hosts/pati0.nix)\n' >> "$CFG"
          printf 'camera_auto_detect=1\n' >> "$CFG"
          printf 'dtoverlay=${cameraOverlay}\n' >> "$CFG"
          printf 'gpu_mem=128\n' >> "$CFG"
        fi
      fi
    '';
  };

  # Load sensor + unicam after boot (harmless if overlay already bound them).
  boot.kernelModules = [
    "bcm2835_unicam"
    "imx219"
    "ov5647"
  ];

  # CMA for libcamera / ISP (default often too tight under load).
  boot.kernelParams = [
    "console=ttyS0,115200n8"
    "console=ttyAMA0,115200n8"
    "console=tty0"
    "cma=256M"
  ];

  # config.txt dtoverlay is not enough under u-boot+FDTDIR — apply rpi kernel overlay at boot.
  systemd.services.pati0-camera-overlay = {
    description = "Apply ${cameraOverlay} CSI device-tree overlay";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "pati0-camera-overlay" ''
        set -e
        DTBS=/run/current-system/dtbs/overlays
        BIN=${pkgs.libraspberrypi}/bin/dtoverlay
        if [ -x "$BIN" ] && [ -f "$DTBS/${cameraOverlay}.dtbo" ]; then
          "$BIN" -d "$DTBS" ${cameraOverlay} || true
        fi
      '';
    };
  };

  # libcamera needs dma_heap + vcsm accessible to video group
  services.udev.extraRules = ''
    SUBSYSTEM=="dma_heap", GROUP="video", MODE="0660"
    KERNEL=="vcsm-cma", GROUP="video", MODE="0660"
  '';

  environment.sessionVariables = {
    # Helps IPA modules resolve under Nix store paths
    LIBCAMERA_IPA_MODULE_PATH = "${pkgs.libcamera}/lib/libcamera";
  };

  # --- users / ssh ---
  users.mutableUsers = true;
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "video"
      "dialout"
      "plugdev" # rtl-sdr udev
      "networkmanager"
    ];
    openssh.authorizedKeys.keys = sshKeys;
  };
  users.users.root.openssh.authorizedKeys.keys = sshKeys;

  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  # --- networking ---
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22
      8081 # patio MJPEG for Home Assistant (LAN)
      1234 # rtl_tcp — RTL-SDR IQ over LAN
    ];
  };

  services.tailscale = {
    enable = true;
    openFirewall = true;
    # first boot: sudo tailscale up --ssh --hostname=pati0
  };

  networking.networkmanager.enable = false; # stick to dhcpcd like stock image
  networking.useNetworkd = false;

  # --- bluetooth (patio fans) ---
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  services.blueman.enable = false;

  # --- RTL-SDR (USB 0bda:2838) — surface on LAN via rtl_tcp ---
  # Blacklists DVB kernel modules so librtlsdr can claim the stick.
  hardware.rtl-sdr.enable = true;
  # Extra blacklist: stock image bound rtl2832_sdr / dvb stack
  boot.blacklistedKernelModules = [
    "dvb_usb_rtl28xxu"
    "dvb_usb_v2"
    "rtl2832"
    "rtl2832_sdr"
    "r820t"
  ];

  # IQ sample server — GQRX / SDR# / dump1090 / etc. connect to pati0:1234
  systemd.services.rtl-tcp = {
    description = "rtl_tcp — RTL-SDR over TCP (LAN)";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network.target"
      "systemd-udev-settle.service"
    ];
    wants = [ "network.target" ];
    serviceConfig = {
      Type = "simple";
      User = "nixos";
      Group = "plugdev";
      SupplementaryGroups = [
        "plugdev"
        "dialout"
      ];
      Restart = "on-failure";
      RestartSec = "5";
      PrivateDevices = false;
      ExecStart = "${pkgs.rtl-sdr}/bin/rtl_tcp -a 0.0.0.0 -p 1234";
      Nice = 5;
    };
  };

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      userServices = true;
    };
  };
  environment.etc."avahi/services/rtl-tcp.service".text = ''
    <?xml version="1.0" standalone='no'?>
    <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
    <service-group>
      <name replace-wildcards="yes">pati0 RTL-SDR (%h)</name>
      <service>
        <type>_rtl_tcp._tcp</type>
        <port>1234</port>
        <txt-record>device=RTL2838</txt-record>
        <txt-record>path=pati0</txt-record>
      </service>
    </service-group>
  '';

  environment.etc."pati0/rtlsdr.env".text = ''
    RTL_TCP_HOST=192.168.68.60
    RTL_TCP_PORT=1234
    RTL_TCP_URL=rtl_tcp=192.168.68.60:1234
    # GQRX: rtl_tcp=192.168.68.60:1234
  '';

  # --- camera + edge packages ---
  environment.systemPackages = with pkgs; [
    git
    tmux
    htop
    usbutils
    pciutils
    ffmpeg
    v4l-utils
    libcamera
    mosquitto
    bluez
    i2c-tools
    libraspberrypi
    raspberrypi-eeprom
    rtl-sdr
    rtl_433
  ]
  ++ lib.optionals (pkgs ? rpicam-apps) [ pkgs.rpicam-apps ]
  ++ lib.optionals (pkgs ? rpicam-apps-lite) [ pkgs.rpicam-apps-lite ];

  # Rook pointers (MQTT / HA) — no secrets
  environment.etc."pati0/rook.env".text = ''
    ROOK_MQTT_HOST=${rookMqttHost}
    ROOK_MQTT_PORT=1883
    ROOK_HA_URL=${rookHaUrl}
    ROOK_TAILSCALE_IP=${rookTs}
    ROOK_TS_DNS=rook.bushbaby-mercat.ts.net
    PATI0_CAMERA_OVERLAY=${cameraOverlay}
  '';

  # Fan inventory (folded from former fans.nix). fanctl daemon TBD (bleak).
  # Amazon Fanbulous-class outdoor fans — BT app + IR; Pi shims via MQTT later.
  environment.etc."pati0/fans.json".text = builtins.toJSON {
    mqtt = {
      host = rookMqttHost;
      port = 1883;
    };
    ha_url = rookHaUrl;
    fans = fans;
  };

  # Camera device contract + HA stream URLs
  environment.etc."pati0/cameras.json".text = builtins.toJSON {
    rook_ha_url = rookHaUrl;
    mjpeg_url = "http://192.168.68.60:8081/stream.mjpg";
    snapshot_url = "http://192.168.68.60:8081/snapshot.jpg";
    devices = [
      {
        name = "patio";
        device = "/dev/video0";
        overlay = cameraOverlay;
      }
    ];
  };

  # Stable multi-client HTTP camera for HA.
  # Previous cam→FIFO→ffmpeg path dropped frames (1.2MB frames vs 64KB pipe)
  # and -listen 1 died after each client. This loop:
  #   1) grabs discrete frames with libcamera cam
  #   2) JPEG encodes with ffmpeg
  #   3) serves latest snapshot + multipart MJPEG to many clients
  environment.etc."pati0/mjpeg-server.py".source = pkgs.writeText "pati0-mjpeg-server.py" ''
    #!/usr/bin/env python3
    import os, io, time, threading, subprocess, signal, sys
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

    WIDTH = int(os.environ.get("PATI0_CAM_WIDTH", "1280"))
    HEIGHT = int(os.environ.get("PATI0_CAM_HEIGHT", "720"))
    FPS = float(os.environ.get("PATI0_CAM_FPS", "8"))
    QUALITY = os.environ.get("PATI0_CAM_QUALITY", "6")  # ffmpeg -q:v (2-31, lower=better)
    HOST = os.environ.get("PATI0_CAM_HOST", "0.0.0.0")
    PORT = int(os.environ.get("PATI0_CAM_PORT", "8081"))
    CAM = os.environ.get("PATI0_CAM_BIN", "cam")
    FFMPEG = os.environ.get("PATI0_FFMPEG_BIN", "ffmpeg")
    RUNDIR = os.environ.get("RUNTIME_DIRECTORY", "/run/pati0-mjpeg")

    latest = None
    lock = threading.Lock()
    stop = threading.Event()

    def log(msg: str) -> None:
        print(msg, flush=True)

    def capture_once(ppm_path: str, jpg_path: str) -> bytes | None:
        # One still via libcamera → PPM → JPEG
        r1 = subprocess.run(
            [
                CAM, "-c1", "--capture=1",
                f"--stream=width={WIDTH},height={HEIGHT},role=viewfinder",
                f"--file={ppm_path}",
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=12,
            check=False,
        )
        if r1.returncode != 0 or not os.path.exists(ppm_path) or os.path.getsize(ppm_path) < 100:
            # cam may write frame-0.bin style if path wrong; also try .ppm extension force
            return None
        # If not ppm magic, still try ffmpeg
        r2 = subprocess.run(
            [
                FFMPEG, "-hide_banner", "-loglevel", "error", "-y",
                "-i", ppm_path,
                "-frames:v", "1",
                "-q:v", QUALITY,
                jpg_path,
            ],
            check=False,
        )
        if r2.returncode != 0 or not os.path.exists(jpg_path):
            return None
        with open(jpg_path, "rb") as f:
            return f.read()

    def capture_loop() -> None:
        global latest
        os.makedirs(RUNDIR, exist_ok=True)
        # Prefer PPM so ffmpeg can decode without raw size guessing
        ppm = os.path.join(RUNDIR, "frame.ppm")
        jpg = os.path.join(RUNDIR, "frame.jpg")
        period = 1.0 / max(FPS, 0.5)
        failures = 0
        while not stop.is_set():
            t0 = time.monotonic()
            try:
                # cam writes PPM when filename ends with .ppm
                data = None
                r1 = subprocess.run(
                    [
                        CAM, "-c1", "--capture=1",
                        f"--stream=width={WIDTH},height={HEIGHT},role=still",
                        f"--file={ppm}",
                    ],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.PIPE,
                    timeout=15,
                    check=False,
                )
                src = ppm
                if r1.returncode != 0 or not os.path.exists(ppm) or os.path.getsize(ppm) < 64:
                    # fallback: raw XRGB dump + size
                    raw = os.path.join(RUNDIR, "frame.raw")
                    r1b = subprocess.run(
                        [
                            CAM, "-c1", "--capture=1",
                            f"--stream=width={WIDTH},height={HEIGHT},role=viewfinder",
                            f"--file={raw}",
                        ],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.PIPE,
                        timeout=15,
                        check=False,
                    )
                    if r1b.returncode != 0 or not os.path.exists(raw):
                        failures += 1
                        if failures <= 3 or failures % 20 == 0:
                            err = (r1.stderr or r1b.stderr or b"").decode("utf-8", "replace")[:300]
                            log(f"capture fail n={failures}: {err}")
                        time.sleep(0.5)
                        continue
                    r2 = subprocess.run(
                        [
                            FFMPEG, "-hide_banner", "-loglevel", "error", "-y",
                            "-f", "rawvideo", "-pix_fmt", "rgba",
                            "-video_size", f"{WIDTH}x{HEIGHT}",
                            "-i", raw,
                            "-frames:v", "1", "-q:v", QUALITY, jpg,
                        ],
                        check=False,
                    )
                else:
                    r2 = subprocess.run(
                        [
                            FFMPEG, "-hide_banner", "-loglevel", "error", "-y",
                            "-i", ppm,
                            "-frames:v", "1", "-q:v", QUALITY, jpg,
                        ],
                        check=False,
                    )
                if r2.returncode == 0 and os.path.exists(jpg):
                    with open(jpg, "rb") as f:
                        data = f.read()
                if data and data[:2] == b"\xff\xd8":
                    with lock:
                        latest = data
                    failures = 0
                else:
                    failures += 1
                # never leave multi-hundred-MB dumps in /run
                for p in (ppm, jpg, os.path.join(RUNDIR, "frame.raw")):
                    try:
                        if os.path.exists(p):
                            os.remove(p)
                    except OSError:
                        pass
            except subprocess.TimeoutExpired:
                failures += 1
                log("capture timeout")
            except Exception as e:
                failures += 1
                log(f"capture exception: {e}")
            dt = time.monotonic() - t0
            time.sleep(max(0.0, period - dt))

    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, fmt, *args):
            # quieter access log
            if self.path.startswith("/snapshot") or self.path.startswith("/stream"):
                return
            log("%s - %s" % (self.address_string(), fmt % args))

        def _send_jpeg(self, data: bytes):
            self.send_response(200)
            self.send_header("Content-Type", "image/jpeg")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store, no-cache, must-revalidate")
            self.send_header("Pragma", "no-cache")
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            path = self.path.split("?", 1)[0]
            if path in ("/", "/health"):
                with lock:
                    ok = latest is not None
                body = b"ok\n" if ok else b"warming\n"
                self.send_response(200 if ok else 503)
                self.send_header("Content-Type", "text/plain")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            if path in ("/snapshot.jpg", "/snapshot", "/snap.jpg"):
                with lock:
                    data = latest
                if not data:
                    self.send_error(503, "No frame yet")
                    return
                self._send_jpeg(data)
                return
            if path in ("/stream.mjpg", "/stream", "/stream.mjpeg"):
                boundary = b"frame"
                self.send_response(200)
                self.send_header(
                    "Content-Type",
                    "multipart/x-mixed-replace; boundary=" + boundary.decode(),
                )
                self.send_header("Cache-Control", "no-store, no-cache, must-revalidate")
                self.send_header("Pragma", "no-cache")
                self.send_header("Connection", "close")
                self.end_headers()
                period = 1.0 / max(FPS, 0.5)
                try:
                    while not stop.is_set():
                        with lock:
                            data = latest
                        if data:
                            header = (
                                b"--" + boundary + b"\r\n"
                                b"Content-Type: image/jpeg\r\n"
                                b"Content-Length: " + str(len(data)).encode() + b"\r\n\r\n"
                            )
                            self.wfile.write(header)
                            self.wfile.write(data)
                            self.wfile.write(b"\r\n")
                            self.wfile.flush()
                        time.sleep(period)
                except (BrokenPipeError, ConnectionResetError):
                    return
                return
            self.send_error(404, "try /snapshot.jpg or /stream.mjpg")

    def main():
        def _sig(*_):
            stop.set()
        signal.signal(signal.SIGTERM, _sig)
        signal.signal(signal.SIGINT, _sig)

        t = threading.Thread(target=capture_loop, name="capture", daemon=True)
        t.start()
        # wait briefly for first frame
        for _ in range(50):
            with lock:
                if latest:
                    break
            time.sleep(0.1)
        httpd = ThreadingHTTPServer((HOST, PORT), Handler)
        httpd.daemon_threads = True
        log(f"pati0 camera http on {HOST}:{PORT} ({WIDTH}x{HEIGHT} @{FPS}fps)")
        try:
            httpd.serve_forever(poll_interval=0.5)
        finally:
            stop.set()
            httpd.server_close()

    if __name__ == "__main__":
        main()
  '';

  systemd.services.pati0-mjpeg = {
    description = "Patio IMX219 HTTP snapshot/MJPEG for Home Assistant";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network.target"
      "pati0-camera-overlay.service"
    ];
    wants = [ "pati0-camera-overlay.service" ];
    path = with pkgs; [
      coreutils
      libcamera
      ffmpeg
      python3
    ];
    serviceConfig = {
      Type = "simple";
      User = "nixos";
      Group = "video";
      SupplementaryGroups = [ "video" ];
      Restart = "always";
      RestartSec = "2";
      RuntimeDirectory = "pati0-mjpeg";
      RuntimeDirectoryMode = "0755";
      PrivateDevices = false;
      ProtectHome = true;
      NoNewPrivileges = true;
      MemoryDenyWriteExecute = false;
      Environment = [
        "LIBCAMERA_IPA_MODULE_PATH=${pkgs.libcamera}/lib/libcamera"
        "PATI0_CAM_BIN=${pkgs.libcamera}/bin/cam"
        "PATI0_FFMPEG_BIN=${pkgs.ffmpeg}/bin/ffmpeg"
        "PATI0_CAM_WIDTH=1280"
        "PATI0_CAM_HEIGHT=720"
        "PATI0_CAM_FPS=8"
        "PATI0_CAM_QUALITY=5"
        "PATI0_CAM_PORT=8081"
      ];
      ExecStart = "${pkgs.python3}/bin/python3 /etc/pati0/mjpeg-server.py";
    };
  };

  # --- nix ---
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [
      "root"
      "nixos"
    ];
  };
  nixpkgs.config.allowUnfree = true;

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  # Lean edge — no HA Core, no Matter server, no Hermes.
  documentation.nixos.enable = false;

  system.stateVersion = "25.05";
}

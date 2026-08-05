# pati0 — patio Raspberry Pi (edge node for Rook's Home Assistant)
#
# Role: NOT a second full HA brain. Rook runs primary HA + Matter + MQTT.
# pati0 sits on the patio and handles:
#   - security camera → streams / events toward rook HA
#   - patio fan-lights (BT/IR shim) → MQTT entities on rook
#   - patio light accents / local sensors
#   - meshtastic (optional)
#
# Network: Tailscale + LAN. MQTT to rook (203.0.113.11).
#
# Flake: not wired as nixosConfigurations.pati0 until aarch64 hardware-configuration
# exists. Build target will be something like:
#   nixos-rebuild switch --flake .#pati0
# from the Pi (or cross from kiss).
{ config, pkgs, lib, ... }:

{
  imports = [
    ../modules/servers/cam.nix
    ../modules/servers/fans.nix
    ../modules/servers/meshtastic.nix
  ];

  networking.hostName = "pati0";

  modules.servers.cam = {
    enable = true;
    rookHaUrl = "http://203.0.113.11:8123";
    # devices = [ { name = "patio_door"; device = "/dev/video0"; } ];
  };

  modules.servers.fans = {
    enable = true;
    mqttHost = "203.0.113.11";
    # Replace XX MAC placeholders after first BT scan on the Pi
  };

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  environment.etc."pati0/rook-mqtt.env".text = ''
    ROOK_MQTT_HOST=203.0.113.11
    ROOK_MQTT_PORT=1883
    ROOK_HA_URL=http://203.0.113.11:8123
    ROOK_TAILSCALE_DNS=chat.example.ts.net
  '';

  environment.systemPackages = with pkgs; [
    git
    tmux
    usbutils
    ffmpeg
    mosquitto
    bluez
  ];
}

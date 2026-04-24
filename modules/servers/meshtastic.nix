# Meshtastic mesh relay node
# Wio Tracker L1 (nRF52840 + LoRa 915MHz) connected via USB to pati0 Pi
# Runs meshtastic-python daemon for CLI management + optional MQTT bridge
# to forward mesh messages to the home network
{ config, pkgs, lib, ... }:

let
  meshtastic = pkgs.python3Packages.buildPythonApplication rec {
    pname = "meshtastic";
    version = "2.5.3";
    src = pkgs.python3Packages.fetchPypi {
      inherit pname version;
      hash = ""; # fill on first build
    };
    propagatedBuildInputs = with pkgs.python3Packages; [
      pyserial
      protobuf
      requests
      pyyaml
      tabulate
      pypubsub
      bleak
    ];
    doCheck = false;
  };
in
{
  # USB serial access for the Wio Tracker
  services.udev.extraRules = ''
    # Wio Tracker L1 nRF52840 USB serial
    SUBSYSTEM=="tty", ATTRS{idVendor}=="2886", ATTRS{idProduct}=="0050", SYMLINK+="meshtastic", MODE="0660", GROUP="dialout"
  '';

  # Meshtastic daemon - keeps the node managed and optionally bridges to MQTT
  systemd.services.meshtastic = {
    description = "Meshtastic Node Manager";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # Configure the node on boot: set name, enable router mode for relay
      ExecStart = pkgs.writeShellScript "meshtastic-setup" ''
        # Wait for USB device
        for i in $(seq 1 30); do
          [ -e /dev/meshtastic ] && break
          sleep 2
        done

        if [ ! -e /dev/meshtastic ]; then
          echo "Meshtastic device not found at /dev/meshtastic"
          exit 1
        fi

        MESH="${meshtastic}/bin/meshtastic --port /dev/meshtastic"

        # Set node name and role
        $MESH --set-owner "pati0-relay"
        $MESH --set lora.region US
        $MESH --set device.role ROUTER

        # Enable position reporting (GPS on Wio)
        $MESH --set position.gps_enabled true
        $MESH --set position.fixed_position false
        $MESH --set position.position_broadcast_secs 900

        echo "Meshtastic node configured as pati0-relay (ROUTER mode)"
      '';
      User = "meshtastic";
      Group = "dialout";
    };
  };

  users.users.meshtastic = {
    isSystemUser = true;
    group = "dialout";
    description = "Meshtastic service user";
  };

  # MQTT bridge (optional, enable when Home Assistant is running on Chat)
  # Forwards mesh messages to MQTT so they're visible on the home network
  # Uncomment when ready:
  #
  # systemd.services.meshtastic-mqtt = {
  #   description = "Meshtastic MQTT Bridge";
  #   after = [ "meshtastic.service" "network-online.target" ];
  #   wantedBy = [ "multi-user.target" ];
  #   serviceConfig = {
  #      ExecStart = "${meshtastic}/bin/meshtastic --port /dev/meshtastic --mqtt-server mqtt://<CHAT_TAILSCALE_IP>:1883 --mqtt-topic meshtastic/";
  #     Restart = "always";
  #     RestartSec = 30;
  #     User = "meshtastic";
  #     Group = "dialout";
  #   };
  # };

  environment.systemPackages = [
    meshtastic
  ];
}

#!/usr/bin/env fish

# ~/.local/bin/vpn   (or anywhere on your $PATH)
# chmod +x this file

set -l INTERFACE surfshark
set -l ENDPOINT 162.252.175.111:51820          # Surfshark New York WireGuard (rock solid)
set -l PUBKEY   bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=
set -l PRIVKEY_FILE ~/.config/surfshark/private.key   # ← change if you store it elsewhere

function show_help
    echo "Usage: vpn [on | off | status]"
end

# ————————————————————————————————
switch $argv[1]
    case on ""
        if test -z "$PRIVKEY_FILE"; or not test -f $PRIVKEY_FILE
            echo "Error: Private key not found at $PRIVKEY_FILE"
            exit 1
        end

        echo "🌊 Connecting to Surfshark New York (WireGuard)…"
        sudo wg-quick up $INTERFACE 2>/dev/null \
        || sudo env \
            WG_QUICK_USERSPACE_IMPLEMENTATION=boringtun \
            INTERFACE=$INTERFACE \
            PRIVATE_KEY=(cat $PRIVKEY_FILE) \
            ADDRESS=10.14.0.2/16 \
            DNS=162.252.172.57,149.154.159.92 \
            PEER_PUBLIC_KEY=$PUBKEY \
            PEER_ENDPOINT=$ENDPOINT \
            ALLOWED_IPS=0.0.0.0/0,::/0 \
            PERSISTENT_KEEPALIVE=25 \
            wg-quick up $INTERFACE

        echo "✓ Connected to New York — enjoy your 15 minutes!"

    case off
        echo "🛑 Disconnecting from Surfshark New York…"
        sudo wg-quick down $INTERFACE 2>/dev/null
        echo "VPN off"

    case status
        if wg show $INTERFACE >/dev/null 2>&1
            wg show $INTERFACE
        else
            echo "Not connected"
        end

    case "*"
        show_help
end

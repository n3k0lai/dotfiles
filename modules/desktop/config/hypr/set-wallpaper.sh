#!/bin/bash

# Wallpaper paths
VIDEO_WALLPAPER="$HOME/.local/share/assets/waves.mp4"
LOCKFILE="/tmp/set-wallpaper.lock"

# Prevent concurrent runs (hypridle on-resume + exec-once can race and stack mpvpaper).
exec 200>"$LOCKFILE"
flock -n 200 || exit 0

# Wait for Hyprland to be ready on normal startup
sleep 2

# Check if mpvpaper is installed and video exists
if command -v mpvpaper &> /dev/null && [ -f "$VIDEO_WALLPAPER" ]; then
    # Kill any existing mpvpaper instances and wait for them to exit.
    # Without the wait, each hypridle DPMS resume spawns another layer surface
    # while the old ones are still shutting down (causes severe compositor glitching
    # when a large/solo window like Firefox covers the monitor).
    killall mpvpaper 2>/dev/null
    for _ in $(seq 1 20); do
        pgrep -x mpvpaper >/dev/null || break
        sleep 0.25
    done
    killall -9 mpvpaper 2>/dev/null
    sleep 0.5
    
    # Get list of connected monitors with their descriptions
    MONITOR_DATA=$(hyprctl monitors -j)
    
    # Start mpvpaper for each connected monitor
    echo "$MONITOR_DATA" | jq -c '.[]' | while read -r monitor; do
        MONITOR_NAME=$(echo "$monitor" | jq -r '.name')
        MONITOR_DESC=$(echo "$monitor" | jq -r '.description')
        
        # Check if this is the vertical monitor (BNQ ZOWIE XL LCD LAG03858SL0)
        if [[ "$MONITOR_DESC" == *"ZOWIE XL LCD LAG03858SL0"* ]]; then
            # For vertical monitor - use panscan to zoom/crop and video-align to position
            nohup mpvpaper -o "no-audio loop panscan=1.0 video-zoom=0.5 video-align-x=1 video-align-y=0" "$MONITOR_NAME" "$VIDEO_WALLPAPER" >/dev/null 2>&1 &
        else
            # For horizontal monitors - standard settings
            nohup mpvpaper -o "no-audio loop" "$MONITOR_NAME" "$VIDEO_WALLPAPER" >/dev/null 2>&1 &
        fi
        disown
    done
fi

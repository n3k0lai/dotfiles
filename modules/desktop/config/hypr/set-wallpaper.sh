#!/bin/bash

# Wallpaper paths
VIDEO_WALLPAPER="$HOME/.local/share/assets/waves.mp4"

# Wait for Hyprland to be ready
sleep 2

# Check if mpvpaper is installed and video exists
if command -v mpvpaper &> /dev/null && [ -f "$VIDEO_WALLPAPER" ]; then
    # Kill any existing mpvpaper instances
    killall mpvpaper 2>/dev/null
    
    # Get list of connected monitors with their descriptions
    MONITOR_DATA=$(hyprctl monitors -j)
    
    # Start mpvpaper for each connected monitor
    echo "$MONITOR_DATA" | jq -c '.[]' | while read -r monitor; do
        MONITOR_NAME=$(echo "$monitor" | jq -r '.name')
        MONITOR_DESC=$(echo "$monitor" | jq -r '.description')
        
        # Check if this is the vertical monitor (BNQ ZOWIE XL LCD LAG03858SL0)
        if [[ "$MONITOR_DESC" == *"ZOWIE XL LCD LAG03858SL0"* ]]; then
            # For vertical monitor - use panscan to zoom/crop and video-align to position
            # panscan=1.0 zooms in to fill the screen by cropping edges
            # video-zoom=0.5 adds additional zoom
            # video-align-x=1 positions to show the right side (1=right, 0=left, 0.5=center)
            mpvpaper -o "no-audio loop panscan=1.0 video-zoom=0.5 video-align-x=1 video-align-y=0" "$MONITOR_NAME" "$VIDEO_WALLPAPER" &
        else
            # For horizontal monitors - standard settings
            mpvpaper -o "no-audio loop" "$MONITOR_NAME" "$VIDEO_WALLPAPER" &
        fi
    done
fi

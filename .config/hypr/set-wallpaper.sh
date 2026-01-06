#!/bin/bash

# Wallpaper paths
VIDEO_WALLPAPER="$HOME/.local/share/assets/waves.mp4"
STATIC_WALLPAPER="$HOME/.local/share/assets/waves.png"

# Check if mpvpaper is installed
if command -v mpvpaper &> /dev/null; then
    # Check if video exists
    if [ -f "$VIDEO_WALLPAPER" ]; then
        echo "Setting animated wallpaper: $VIDEO_WALLPAPER"
        # Kill any existing mpvpaper instances
        killall mpvpaper 2>/dev/null
        # Start mpvpaper for each monitor
        # Adjust monitor names based on your setup
        mpvpaper -o "no-audio loop" '*' "$VIDEO_WALLPAPER" &
        exit 0
    fi
fi

# Fallback to static wallpaper with hyprpaper
if [ -f "$STATIC_WALLPAPER" ]; then
    echo "Falling back to static wallpaper: $STATIC_WALLPAPER"
    # Kill any existing mpvpaper instances
    killall mpvpaper 2>/dev/null
    # Use hyprctl to set wallpaper (requires hyprpaper to be running)
    if ! pgrep -x hyprpaper > /dev/null; then
        echo "Starting hyprpaper..."
        hyprpaper &
        sleep 1  # Give hyprpaper time to initialize
    fi
    hyprctl hyprpaper preload "$STATIC_WALLPAPER"
    hyprctl hyprpaper wallpaper ",$STATIC_WALLPAPER"
else
    echo "Error: No wallpaper files found!"
    echo "Expected: $VIDEO_WALLPAPER or $STATIC_WALLPAPER"
    exit 1
fi

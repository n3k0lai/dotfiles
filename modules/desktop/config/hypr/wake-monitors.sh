#!/bin/bash
# Wake monitors after hypridle DPMS idle timeout or system resume.
# The vertical ZOWIE (transform 3) often stays black after a plain "dpms on"
# on the NVIDIA stack; a brief per-monitor DPMS toggle recovers it.

VERT=$(hyprctl monitors -j | jq -r '.[] | select(.description | test("ZOWIE XL LCD")) | .name' | head -1)

hyprctl dispatch dpms on

if [[ -n "$VERT" ]]; then
    hyprctl dispatch dpms off "$VERT"
    sleep 0.3
    hyprctl dispatch dpms on "$VERT"
fi

bash ~/.config/hypr/set-wallpaper.sh

# Layer-shell clients (eww) often lose their surface across DPMS on NVIDIA.
# Re-open the sidebar if the daemon is up but the window is gone.
if [[ -x "$HOME/.config/eww/eww-sidebar" ]]; then
    sleep 0.5
    "$HOME/.config/eww/eww-sidebar" ensure >/dev/null 2>&1 &
fi

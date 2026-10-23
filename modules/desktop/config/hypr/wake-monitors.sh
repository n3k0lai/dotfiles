#!/bin/bash
# Wake monitors after hypridle DPMS idle timeout or system resume.
#
# The vertical ZOWIE sits behind a powered DisplayPort-to-DVI converter.
# hypridle's dpms-on lights the panel before that converter re-locks
# dual-link. The NVIDIA CRTC then sticks on one black framebuffer and
# never page-flips, while Hyprland still maps workspaces onto it.
# Disabling the output in Hyprland is not enough: sysfs stays
# "connected". Forcing the connector off and reprobing drops the link
# so the next modeset actually presents frames.

VERT_DESC="desc:BNQ ZOWIE XL LCD LAG03858SL0"
# Keep in sync with monitors-kiss.conf (144 Hz, transform 3, vrr off).
VERT_SPEC="1920x1080@144, 4480x600, 1, transform, 3, vrr, 0"

hyprctl dispatch dpms on

if hyprctl monitors all -j | jq -e 'any(.[]; .description | contains("ZOWIE XL LCD"))' >/dev/null; then
    hyprctl keyword monitor "${VERT_DESC}, disable"
    # Kernel connector name matches Hyprland's DP-2 on this GPU.
    VERT_SYSFS=$(echo /sys/class/drm/card*-DP-2)
    if [[ -e "$VERT_SYSFS/status" ]] && sudo -n true 2>/dev/null; then
        sudo -n sh -c "echo off > '$VERT_SYSFS/status'"
        sleep 2
        sudo -n sh -c "echo detect > '$VERT_SYSFS/status'"
        sleep 1
    else
        sleep 2
    fi
    hyprctl keyword monitor "${VERT_DESC}, ${VERT_SPEC}"
    VERT=$(hyprctl monitors -j | jq -r '.[] | select(.description | contains("ZOWIE XL LCD")) | .name' | head -1)
    if [[ -n "$VERT" ]]; then
        # keyword monitor does not reapply the workspace rules.
        for ws in 4 5 6 9; do
            hyprctl dispatch moveworkspacetomonitor "$ws" "$VERT" >/dev/null
        done
    fi
fi

bash ~/.config/hypr/set-wallpaper.sh

# Layer-shell clients (eww) often lose their surface across DPMS on NVIDIA.
# Re-open the sidebar if the daemon is up but the window is gone.
if [[ -x "$HOME/.config/eww/eww-sidebar" ]]; then
    sleep 0.5
    "$HOME/.config/eww/eww-sidebar" ensure >/dev/null 2>&1 &
fi

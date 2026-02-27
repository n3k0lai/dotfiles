#!/usr/bin/env fish

# Listen to hyprland workspace events and output workspace info as JSON
function get_workspaces
    set active_id (hyprctl activeworkspace -j | jq -r '.id')
    # Only emit workspaces that have windows, plus always include the active one
    hyprctl workspaces -j | jq -c \
        --argjson active "$active_id" \
        '[.[] | select(.windows > 0 or .id == $active) | {id: .id, windows: .windows}] | sort_by(.id)'
end

# Initial output
get_workspaces

# Listen for workspace changes
socat -u UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock - | while read -l line
    get_workspaces
end

#!/usr/bin/env fish

# Listen to hyprland events and output current workspace
function get_current_workspace
    hyprctl activeworkspace -j | jq -r '.id'
end

# Initial output
get_current_workspace

# Listen for workspace changes
socat -u UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock - | while read -l line
    if string match -q "workspace>>*" $line
        get_current_workspace
    end
end

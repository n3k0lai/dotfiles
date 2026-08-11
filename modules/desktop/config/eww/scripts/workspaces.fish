#!/usr/bin/env fish

# Listen to hyprland workspace events and output workspace info as JSON.
# Only re-emit on events that can change workspace occupancy / focus — not
# on windowtitle/activewindow spam (those fire many times per second).

function get_workspaces
    set active_id (hyprctl activeworkspace -j | jq -r '.id')
    # Only emit workspaces that have windows, plus always include the active one
    hyprctl workspaces -j | jq -c \
        --argjson active "$active_id" \
        '[.[] | select(.windows > 0 or .id == $active) | {id: .id, windows: .windows}] | sort_by(.id)'
end

# Initial output
get_workspaces

set -l sock "$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
if not test -S $sock
    exit 1
end

socat -u UNIX-CONNECT:$sock - | while read -l line
    # Occupancy / focus only — skip windowtitle/activewindow spam
    switch $line
        case 'workspace>>*' 'workspacev2>>*' \
             'focusedmon>>*' 'focusedmonv2>>*' \
             'createworkspace>>*' 'createworkspacev2>>*' \
             'destroyworkspace>>*' 'destroyworkspacev2>>*' \
             'openwindow>>*' 'closewindow>>*' \
             'movewindow>>*' 'movewindowv2>>*' \
             'urgent>>*'
            get_workspaces
    end
end

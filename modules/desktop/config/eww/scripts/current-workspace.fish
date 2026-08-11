#!/usr/bin/env fish

# Listen to hyprland events and output current workspace id.
# Ignore title/noise events; only react to focus / workspace changes.

function get_current_workspace
    hyprctl activeworkspace -j | jq -r '.id'
end

# Initial output
get_current_workspace

set -l sock "$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
if not test -S $sock
    exit 1
end

socat -u UNIX-CONNECT:$sock - | while read -l line
    switch $line
        case 'workspace>>*' 'workspacev2>>*' \
             'focusedmon>>*' 'focusedmonv2>>*' \
             'activespecial>>*'
            get_current_workspace
    end
end

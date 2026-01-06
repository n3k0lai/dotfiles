#!/usr/bin/env fish

# Listen to hyprland workspace events and output workspace info as JSON
function get_workspaces
    set workspaces_json "["
    set first true
    
    for i in (seq 1 10)
        set windows (hyprctl workspaces -j | jq -r ".[] | select(.id == $i) | .windows")
        if test -z "$windows"
            set windows 0
        end
        
        if not $first
            set workspaces_json "$workspaces_json,"
        end
        set workspaces_json "$workspaces_json{\"id\":$i,\"windows\":$windows}"
        set first false
    end
    
    set workspaces_json "$workspaces_json]"
    echo $workspaces_json
end

# Initial output
get_workspaces

# Listen for workspace changes
socat -u UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock - | while read -l line
    get_workspaces
end

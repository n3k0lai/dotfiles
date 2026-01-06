# a windows RDP wrapper
function werk --argument-names cmd
    # Force universal vars to be inherited even in non-login shells
    if not set -q WORK_IP
        source ~/.ssh/workcreds.fish 2>/dev/null
        or begin
            echo "creds not found, choom."
            return 1
        end
    end

    echo "logging into $WORK_IP"
    
    set -l clip_opts \
        /kbd:remap:0x5B=0x0,remap:0x5C=0x0 \
        /cert:ignore \
        +home-drive \
        /dynamic-resolution
    
    switch "$cmd"
        # case for fullscreen (legacy behavior)
        case -l
            xfreerdp /w:2560 /h:1440 /u:$WORK_USR /p:$WORK_PWD /v:$WORK_IP /title:werk-fullscreen $clip_opts &
        # case for small resolution
        case -s
            xfreerdp /w:1920 /h:1080 /u:$WORK_USR /p:$WORK_PWD /v:$WORK_IP /title:werk-small $clip_opts &
        # default: respect hyprland tiling (no fixed size)
        case "*"
            xfreerdp /u:$WORK_USR /p:$WORK_PWD /v:$WORK_IP /title:werk-tiled $clip_opts &
    end
    
    disown
end

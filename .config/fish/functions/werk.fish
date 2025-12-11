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
        /clipboard \
        +clipboard \
        # /dynamic-resolution \
        # /bpp:32 \
        /cert:ignore \
        +home-drive
    
    switch "$cmd"
        # case for local ip
        case -s
            sdl-freerdp /w:1920 /h:1080 /u:$WORK_USR /p:$WORK_PWD /v:$WORK_IP $clip_opts
        case "*"
            sdl-freerdp /w:2560 /h:1440 /u:$WORK_USR /p:$WORK_PWD /v:$WORK_IP $clip_opts
    end
end

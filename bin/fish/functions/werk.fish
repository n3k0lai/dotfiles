# Windows RDP wrapper — uses xfreerdp (XWayland).
# Hyprland window rules in hyprland.conf match on /title: strings.
function werk --argument-names cmd
    switch "$cmd"
        case -k --kill
            __werk_kill
            return $status
        case -h --help
            echo "usage: werk [-l|-s|-k]"
            echo "  (none)  tiled session on workspace 3 (default)"
            echo "  -l      fullscreen 2560x1440"
            echo "  -s      tiled 1920x1080"
            echo "  -k      kill all werk RDP sessions"
            return 0
    end

    if not set -q WORK_IP
        source /run/agenix/work_creds 2>/dev/null
        or begin
            echo "creds not found, choom."
            return 1
        end
    end

    set -l existing (__werk_pids)
    if test (count $existing) -gt 0
        echo "killing "(count $existing)" existing werk session(s)..."
        __werk_kill --quiet
        sleep 0.5
    end

    echo "logging into $WORK_IP"

    set -l clip_opts \
        +clipboard \
        /kbd:remap:0x5B=0x0,remap:0x5C=0x0 \
        /cert:ignore \
        +home-drive \
        /dynamic-resolution \
        /smartcard \
        /audio-mode:0 \
        /microphone

    switch "$cmd"
        case -l
            xfreerdp /w:2560 /h:1440 /u:$WORK_USR /p:$WORK_PWD /v:$WORK_IP /title:werk-fullscreen $clip_opts &
        case -s
            xfreerdp /w:1920 /h:1080 /u:$WORK_USR /p:$WORK_PWD /v:$WORK_IP /title:werk-small $clip_opts &
        case "*"
            xfreerdp /u:$WORK_USR /p:$WORK_PWD /v:$WORK_IP /title:werk-tiled $clip_opts &
    end

    disown
end

function __werk_pids
    pgrep -f '/title:werk-' 2>/dev/null
end

function __werk_kill --argument-names quiet
    set -l pids (__werk_pids)
    if test (count $pids) -eq 0
        test "$quiet" != --quiet; and echo "no werk sessions running"
        return 0
    end

    for pid in $pids
        test "$quiet" != --quiet; and echo "killing werk $pid"
        kill -9 $pid 2>/dev/null
    end

    hyprctl clients -j 2>/dev/null | python3 -c "
import json, subprocess, sys
for c in json.load(sys.stdin):
    if c.get('class') in ('sdl-freerdp', 'xfreerdp'):
        subprocess.run(
            ['hyprctl', 'dispatch', 'closewindow', f\"pid:{c['pid']}\"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
" 2>/dev/null

    test "$quiet" != --quiet; and echo "done"
end
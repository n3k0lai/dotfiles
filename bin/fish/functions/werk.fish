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

    # Seed /w /h from the focused monitor so the first framebuffer is not
    # the Windows login-dialog size (that is what letterboxes the tile).
    set -l mon_w 1920
    set -l mon_h 1080
    set -l dims (hyprctl monitors -j 2>/dev/null | jq -r '
        .[] | select(.focused == true)
        | "\(.width - .reserved[0] - .reserved[2]) \(.height - .reserved[1] - .reserved[3])"
    ')
    if test (count $dims) -eq 2
        set mon_w $dims[1]
        set mon_h $dims[2]
    end

    switch "$cmd"
        case -l
            xfreerdp /w:2560 /h:1440 /u:$WORK_USR /p:$WORK_PWD /v:$WORK_IP /title:werk-fullscreen $clip_opts &
        case -s
            xfreerdp /w:1920 /h:1080 /u:$WORK_USR /p:$WORK_PWD /v:$WORK_IP /title:werk-small $clip_opts &
        case "*"
            xfreerdp /w:$mon_w /h:$mon_h /u:$WORK_USR /p:$WORK_PWD /v:$WORK_IP /title:werk-tiled $clip_opts &
    end

    disown
    # Login modal keeps the small size; nudge after map + after desktop
    # so /dynamic-resolution actually fires (same as opening a terminal).
    __werk_reflow_loop &
    disown
end

function __werk_nudge --argument-names addr
    hyprctl dispatch focuswindow "address:$addr" >/dev/null
    hyprctl dispatch resizeactive 2 2 >/dev/null
    sleep 0.12
    hyprctl dispatch resizeactive -2 -2 >/dev/null
end

function __werk_reflow_loop
    set -l tries 0
    set -l seen 0
    while test $tries -lt 50
        set -l addr (hyprctl clients -j 2>/dev/null | jq -r '
            .[] | select((.class | test("freerdp"; "i")) and (.title | test("werk-"; "i")))
            | .address' | head -1)
        if test -n "$addr"
            set seen (math $seen + 1)
            if contains $seen 1 3 6 12 20
                __werk_nudge $addr
            end
        end
        sleep 0.5
        set tries (math $tries + 1)
    end
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
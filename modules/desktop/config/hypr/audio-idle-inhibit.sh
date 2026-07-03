#!/bin/bash
# Manage sway-audio-idle-inhibit for hypridle.
# Started while unlocked so DPMS is blocked during media playback.
# Stopped on lock so the bedtime flow (lock + walk away) still DPMS-offs.

case "${1:-}" in
    start)
        pgrep -f '/sway-audio-idle-inhibit$' >/dev/null && exit 0
        nohup sway-audio-idle-inhibit >/dev/null 2>&1 &
        disown
        ;;
    stop)
        pkill -f '/sway-audio-idle-inhibit$' 2>/dev/null
        ;;
    *)
        echo "usage: $0 {start|stop}" >&2
        exit 1
        ;;
esac
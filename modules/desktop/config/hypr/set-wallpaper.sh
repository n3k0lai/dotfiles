#!/bin/bash
# Video wallpaper via mpvpaper. mpvpaper 1.8 leaks ~2.4 MB/min per instance
# while looping (GL fences + software-decode frame pool) and filled 60+ GiB
# here after a few days. Mitigations:
#   - mpv flags: GPU decode, no cache, loop-file (not a growing playlist)
#   - kill by wrapped *and* unwrapped comm (Nix wrapProgram truncates comm)
#   - RSS watchdog recycles any instance that still grows

VIDEO_WALLPAPER="$HOME/.local/share/assets/waves.mp4"
LOCKFILE="/tmp/set-wallpaper.lock"
WATCHDOG_PIDFILE="${XDG_RUNTIME_DIR:-/tmp}/mpvpaper-watchdog.pid"
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
# auto-copy hwdec sits ~500 MiB per display at start; 1.8 still leaks on top of that.
# Recycle well before the old 12 GiB-per-instance blow-up, but above the working set.
RSS_LIMIT_KB=$((1536 * 1024))
WATCHDOG_INTERVAL=60

# config=no: ignore ~/.config/mpv (a user cache=yes would undo the caps).
# hwdec=auto-copy-safe: GPU decode with copy-back — zero-copy EGL interop is
#   flaky on NVIDIA+Wayland and is the GL-fence leak path in mpvpaper < 1.9.
# cache=no + tiny demuxer: local 6 MiB loop does not need 150 MiB of packets.
# loop-file=inf: loop this file; plain `loop` is a playlist loop.
MPV_COMMON="config=no no-audio loop-file=inf hwdec=auto-copy-safe cache=no demuxer-max-bytes=32MiB demuxer-max-back-bytes=16MiB interpolation=no osd-level=0 osc=no terminal=no"

mpvpaper_pids() {
    pgrep -x mpvpaper 2>/dev/null
    pgrep -x '\.mpvpaper-wrapp' 2>/dev/null
}

mpvpaper_running() {
    pgrep -x mpvpaper >/dev/null 2>&1 || pgrep -x '\.mpvpaper-wrapp' >/dev/null 2>&1
}

hyprland_alive() {
    if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        [ -S "${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket.sock" ]
        return
    fi
    pgrep -x Hyprland >/dev/null 2>&1 || pgrep -x '\.Hyprland-wrapp' >/dev/null 2>&1
}

stop_mpvpaper() {
    # Nix wrapProgram makes comm `.mpvpaper-wrapp`; killall mpvpaper misses it.
    killall -TERM mpvpaper .mpvpaper-wrapp 2>/dev/null
    for _ in $(seq 1 20); do
        mpvpaper_running || break
        sleep 0.25
    done
    killall -KILL mpvpaper .mpvpaper-wrapp 2>/dev/null
}

rss_over_limit() {
    local pid rss
    for pid in $(mpvpaper_pids); do
        rss=$(awk '/^VmRSS:/{print $2}' "/proc/$pid/status" 2>/dev/null) || continue
        if [ "${rss:-0}" -gt "$RSS_LIMIT_KB" ]; then
            return 0
        fi
    done
    return 1
}

watchdog_alive() {
    local pid
    pid=$(cat "$WATCHDOG_PIDFILE" 2>/dev/null) || return 1
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

run_watchdog() {
    echo $$ >"$WATCHDOG_PIDFILE"
    trap 'rm -f "$WATCHDOG_PIDFILE"' EXIT
    while sleep "$WATCHDOG_INTERVAL"; do
        hyprland_alive || exit 0
        mpvpaper_running || continue
        if rss_over_limit; then
            bash "$SCRIPT_PATH" --recycle
        fi
    done
}

start_watchdog() {
    watchdog_alive && return 0
    nohup bash "$SCRIPT_PATH" --watchdog >/dev/null 2>&1 &
    disown
}

if [ "${1:-}" = --watchdog ]; then
    run_watchdog
    exit 0
fi

# Prevent concurrent runs (hypridle on-resume + exec-once + watchdog recycle).
exec 200>"$LOCKFILE"
flock -n 200 || exit 0

if [ "${1:-}" != --recycle ]; then
    # exec-once can beat hyprctl; retry instead of a blind sleep 2.
    for _ in $(seq 1 20); do
        hyprctl monitors -j >/dev/null 2>&1 && break
        sleep 0.25
    done
fi

if ! command -v mpvpaper >/dev/null || [ ! -f "$VIDEO_WALLPAPER" ]; then
    exit 0
fi

stop_mpvpaper
sleep 0.5

MONITOR_DATA=$(hyprctl monitors -j) || exit 0

while read -r monitor; do
    MONITOR_NAME=$(echo "$monitor" | jq -r '.name')
    MONITOR_DESC=$(echo "$monitor" | jq -r '.description')

    if [[ "$MONITOR_DESC" == *"ZOWIE XL LCD LAG03858SL0"* ]]; then
        MPV_OPTS="$MPV_COMMON panscan=1.0 video-zoom=0.5 video-align-x=1 video-align-y=0"
    else
        MPV_OPTS="$MPV_COMMON"
    fi

    # -p: pause when the wallpaper is fully covered (saves CPU; leak is per-frame).
    nohup mpvpaper -p -o "$MPV_OPTS" "$MONITOR_NAME" "$VIDEO_WALLPAPER" >/dev/null 2>&1 &
    disown
done < <(echo "$MONITOR_DATA" | jq -c '.[]')

start_watchdog

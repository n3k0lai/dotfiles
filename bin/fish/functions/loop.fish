# Play video(s) looped and muted. Globs expand to one mpv per file.
# Windows use app-id mpv-loop so Hyprland's `class:^(mpv)$` → workspace 4
# rule does not steal them; they stay on the calling terminal's workspace.
function loop --description 'Play video(s) looped, muted, on this workspace'
    if not set -q argv[1]
        echo "Usage: loop <file> [file...]" >&2
        echo "  globs ok:  loop test*" >&2
        return 1
    end

    set -l files
    for pattern in $argv
        if test -f $pattern
            set -a files $pattern
            continue
        end
        set -l expanded
        eval set expanded $pattern
        set -l matched 0
        for f in $expanded
            if test -f $f
                set -a files $f
                set matched 1
            end
        end
        if test $matched -eq 0
            echo "loop: no files match: $pattern" >&2
            return 1
        end
    end

    set -l ws (hyprctl activeworkspace -j 2>/dev/null | jq -r '.id // empty')
    set -l opts --loop=inf --mute --really-quiet --force-window=immediate \
        --wayland-app-id=mpv-loop --x11-name=mpv-loop

    for f in $files
        set -l path (path resolve $f)
        set -l title "loop:"(basename $path)
        if test -n "$ws"
            set -l qpath (string join '' "'" (string replace -a "'" "'\\''" -- $path) "'")
            set -l qtitle (string join '' "'" (string replace -a "'" "'\\''" -- $title) "'")
            hyprctl dispatch exec "[workspace $ws] mpv $opts --title=$qtitle -- $qpath" >/dev/null
        else
            mpv $opts --title=$title -- $path &
            disown
        end
    end
end

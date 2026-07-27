function loop --description 'Play a video looped, muted, in the background'
    if not set -q argv[1]
        echo "Usage: loop <file.mp4>" >&2
        return 1
    end

    if not test -f $argv[1]
        echo "loop: file not found: $argv[1]" >&2
        return 1
    end

    mpv --loop=inf --mute --really-quiet $argv &
    disown
end

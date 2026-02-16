function nanoloop-fade -d "Crossfade between nanoloop PipeWire sinks"
    # Get node IDs for the output sides of the loopbacks
    set -l id_a (pw-dump | jq -r '.[] | select(.info.props["node.name"] == "nanoloop-a-output") | .id' 2>/dev/null)
    set -l id_b (pw-dump | jq -r '.[] | select(.info.props["node.name"] == "nanoloop-b-output") | .id' 2>/dev/null)

    if test -z "$id_a" -o -z "$id_b"
        echo "Could not find nanoloop PipeWire sinks."
        echo "Make sure PipeWire is running and nanoloop sinks are configured."
        return 1
    end

    # No args: show current volumes
    if test (count $argv) -eq 0
        set -l vol_a (wpctl get-volume $id_a 2>/dev/null | string match -r '[\d.]+')
        set -l vol_b (wpctl get-volume $id_b 2>/dev/null | string match -r '[\d.]+')
        echo "nanoloop-a (id $id_a): $vol_a"
        echo "nanoloop-b (id $id_b): $vol_b"
        echo ""
        echo "Usage: nanoloop-fade <0.0-1.0>"
        echo "  0.0 = full A, 1.0 = full B, 0.5 = equal mix"
        return 0
    end

    set -l pos $argv[1]

    # Validate input is a number between 0.0 and 1.0
    if not string match -qr '^[01]?\.\d+$|^[01]$|^[01]\.$' $pos
        echo "Position must be a number between 0.0 and 1.0"
        return 1
    end

    # Calculate volumes: A fades out as position increases, B fades in
    set -l vol_a (math "1.0 - $pos")
    set -l vol_b $pos

    wpctl set-volume $id_a $vol_a
    wpctl set-volume $id_b $vol_b

    echo "Crossfader: A=$vol_a B=$vol_b"
end

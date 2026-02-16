function nanoloop -d "Launch dual mGBA instances for nanoloop crossfading"
    set -l rom_dir ~/Code/tunes/roms/nanoloop

    if not test -d $rom_dir
        echo "ROM directory not found: $rom_dir"
        echo "Run tunes-pull to clone the tunes repo first."
        return 1
    end

    if test (count $argv) -eq 0
        echo "Available ROMs:"
        for rom in $rom_dir/*.gba
            echo "  "(basename $rom)
        end
        echo ""
        echo "Usage: nanoloop <rom>"
        return 0
    end

    set -l rom $argv[1]

    # Resolve rom path - check if it's a full path or just a name
    if not test -f $rom
        # Try with .gba extension
        if test -f $rom_dir/$rom
            set rom $rom_dir/$rom
        else if test -f $rom_dir/$rom.gba
            set rom $rom_dir/$rom.gba
        else
            echo "ROM not found: $rom"
            return 1
        end
    end

    echo "Launching nanoloop with: "(basename $rom)
    echo "  Instance A → nanoloop-a"
    echo "  Instance B → nanoloop-b"

    # Reset crossfader to center
    nanoloop-fade 0.5

    # Launch two mGBA instances routed to different PipeWire sinks
    PIPEWIRE_NODE=nanoloop-a mgba-qt $rom &
    PIPEWIRE_NODE=nanoloop-b mgba-qt $rom &

    echo "Use nanoloop-fade <0.0-1.0> to crossfade between instances."
end

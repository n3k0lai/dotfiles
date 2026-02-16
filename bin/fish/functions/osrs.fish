function osrs
    # Set XDG directories for RuneLite
    set -x XDG_CONFIG_HOME (test -n "$XDG_CONFIG_HOME"; and echo "$XDG_CONFIG_HOME"; or echo "$HOME/.config")
    set -x XDG_DATA_HOME (test -n "$XDG_DATA_HOME"; and echo "$XDG_DATA_HOME"; or echo "$HOME/.local/share")
    
    # Create RuneLite directory structure
    mkdir -p "$XDG_DATA_HOME/runelite"
    
    # Check if user wants to configure Jagex account
    if test "$argv[1]" = "--jagex-setup"
        set settings_file "$HOME/.runelite/settings.properties"
        mkdir -p "$HOME/.runelite"
        
        echo "Setting up Jagex Launcher integration..."
        echo "Please provide the path to your Jagex Launcher executable:"
        read -P "Jagex Launcher path: " jagex_path
        
        if test -n "$jagex_path"
            echo "configured-client-path=$jagex_path" >> "$settings_file"
            echo "launcher-arguments=--configure" >> "$settings_file"
            echo "Configuration saved to $settings_file"
            echo "Now launch OSRS via Steam to use Jagex account"
        end
    else
        # Launch RuneLite
        runelite $argv
    end
end

function set_wallpaper --description 'Set animated or static wallpaper on Hyprland/bspwm'
    # Wallpaper paths (can be overridden by theme modules)
    set -l video_wallpaper "$HOME/.local/share/assets/waves.mp4"
    set -l static_wallpaper "$HOME/.local/share/assets/waves.png"
    
    # Detect which compositor is running
    if set -q HYPRLAND_INSTANCE_SIGNATURE
        # Delegate to the shared bash script (has flock + mpvpaper cleanup).
        bash ~/.config/hypr/set-wallpaper.sh
        return $status

    else if set -q DESKTOP_SESSION; and string match -q "*bspwm*" -- "$DESKTOP_SESSION"
        # bspwm detected - use feh or nitrogen for static wallpaper
        if test -f "$static_wallpaper"
            if command -v feh &> /dev/null
                feh --bg-scale "$static_wallpaper"
                echo "✓ Wallpaper set on bspwm (feh)"
            else if command -v nitrogen &> /dev/null
                nitrogen --set-scaled "$static_wallpaper"
                echo "✓ Wallpaper set on bspwm (nitrogen)"
            else
                echo "⚠ No wallpaper setter found (install feh or nitrogen)"
            end
        else
            echo "⚠ No wallpaper file found at $static_wallpaper"
        end
        
    else
        echo "⚠ No supported compositor detected (Hyprland or bspwm)"
    end
end
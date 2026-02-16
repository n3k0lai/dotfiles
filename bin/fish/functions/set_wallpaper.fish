function set_wallpaper --description 'Set animated or static wallpaper on Hyprland/bspwm'
    # Wallpaper paths (can be overridden by theme modules)
    set -l video_wallpaper "$HOME/.local/share/assets/waves.mp4"
    set -l static_wallpaper "$HOME/.local/share/assets/waves.png"
    
    # Wait for compositor to be ready
    sleep 2
    
    # Detect which compositor is running
    if set -q HYPRLAND_INSTANCE_SIGNATURE
        # Hyprland detected - use mpvpaper for animated wallpaper
        if command -v mpvpaper &> /dev/null; and test -f "$video_wallpaper"
            # Kill any existing mpvpaper instances
            killall mpvpaper 2>/dev/null
            
            # Get list of connected monitors with their descriptions
            set monitor_data (hyprctl monitors -j)
            
            # Start mpvpaper for each connected monitor
            echo "$monitor_data" | jq -c '.[]' | while read -r monitor
                set monitor_name (echo "$monitor" | jq -r '.name')
                set monitor_desc (echo "$monitor" | jq -r '.description')
                
                # Check if this is the vertical monitor (BNQ ZOWIE XL LCD LAG03858SL0)
                if string match -q "*ZOWIE XL LCD LAG03858SL0*" -- "$monitor_desc"
                    # For vertical monitor - use panscan to zoom/crop and video-align to position
                    mpvpaper -o "no-audio loop panscan=1.0 video-zoom=0.5 video-align-x=1 video-align-y=0" "$monitor_name" "$video_wallpaper" &
                else
                    # For horizontal monitors - standard settings
                    mpvpaper -o "no-audio loop" "$monitor_name" "$video_wallpaper" &
                end
            end
            
            echo "✓ Animated wallpaper set on Hyprland monitors"
        else if test -f "$static_wallpaper"
            # Fallback to static wallpaper with hyprpaper
            if command -v hyprpaper &> /dev/null
                hyprpaper &
                echo "✓ Static wallpaper set on Hyprland"
            end
        else
            echo "⚠ No wallpaper files found at $video_wallpaper or $static_wallpaper"
        end
        
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

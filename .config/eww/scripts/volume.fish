#!/usr/bin/env fish

# Get volume info from wpctl
if test "$argv[1]" = "icon"
    # Get mute status and volume for icon
    set muted (wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep MUTED)
    set volume (wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print int($2 * 100)}')
    
    if test -n "$muted"
        echo "󰖁"
    else if test $volume -eq 0
        echo "󰖁"
    else if test $volume -lt 33
        echo "󰕿"
    else if test $volume -lt 66
        echo "󰖀"
    else
        echo "󰕾"
    end
else
    # Get volume percentage
    wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print int($2 * 100)}'
end

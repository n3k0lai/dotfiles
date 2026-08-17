#!/usr/bin/env fish

# eww :monitor / --screen match string.
# kiss pins the BenQ. Elsewhere use the model (eww lists blade as
# `[0] 0x14B8`, not the full Hyprland description).
switch (hostname)
    case kiss
        echo "BenQ EX2710Q"
    case '*'
        hyprctl monitors -j 2>/dev/null | jq -r '
          (map(select(.focused == true)) + .)[0]
          | .model // .name // "0"
        '
end

#!/usr/bin/env fish

# Get current fcitx5 input method and display as short label
set im (fcitx5-remote -n 2>/dev/null)

switch "$im"
    case "keyboard-us"
        echo "EN"
    case "pinyin"
        echo "中"
    case "mozc"
        echo "日"
    case "*"
        echo "EN"
end

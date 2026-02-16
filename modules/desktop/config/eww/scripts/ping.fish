#!/usr/bin/env fish

# Ping script for eww
# Measures latency to 1.1.1.1

set -l target "1.1.1.1"
set -l ping_result (ping -c 1 -W 1 $target 2>/dev/null | grep "time=" | awk -F'time=' '{print $2}' | awk '{print $1}')

if test -n "$ping_result"
    printf "%.0f" $ping_result
else
    echo "---"
end

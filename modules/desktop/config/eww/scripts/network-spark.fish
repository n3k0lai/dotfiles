#!/usr/bin/env fish

# Network sparkline script for eww
# Usage: network-spark.fish [up|down]
# Outputs a fixed-width sparkline showing recent network rate history

set -l direction $argv[1]
if test -z "$direction"
    set direction down
end

# Find active network interface
set -l interface (ip route | grep default | awk '{print $5}' | head -n1)

if test -z "$interface"
    set interface (ip link show | grep "state UP" | grep -v "lo:" | head -n1 | awk -F: '{print $2}' | string trim)
end

if test -z "$interface"
    echo "▁▁▁▁▁▁▁▁▁▁"
    exit 0
end

# Select bytes file based on direction
if test "$direction" = "up"
    set bytes_file "/sys/class/net/$interface/statistics/tx_bytes"
else
    set bytes_file "/sys/class/net/$interface/statistics/rx_bytes"
end

if not test -f $bytes_file
    echo "▁▁▁▁▁▁▁▁▁▁"
    exit 0
end

set -l current_bytes (cat $bytes_file)
set -l current_time (date +%s)

# Cache and history dirs
set -l cache_dir "/tmp/eww-network-$USER"
mkdir -p $cache_dir

set -l bytes_cache "$cache_dir/{$direction}_bytes"
set -l time_cache "$cache_dir/{$direction}_time"
set -l history_file "$cache_dir/{$direction}_history"

set -l max_points 18

# Calculate rate from last reading
set -l rate 0
if test -f $bytes_cache -a -f $time_cache
    set -l old_bytes (cat $bytes_cache)
    set -l old_time (cat $time_cache)
    set -l time_diff (math "$current_time - $old_time")

    if test $time_diff -gt 0
        set -l bytes_diff (math "$current_bytes - $old_bytes")
        # Rate in KB/s
        set rate (math "$bytes_diff / $time_diff / 1024")
        if test $rate -lt 0
            set rate 0
        end
    end
end

# Update bytes/time cache
echo $current_bytes > $bytes_cache
echo $current_time > $time_cache

# Read existing history
set -l rates
if test -f $history_file
    set rates (string split \n -- (cat $history_file) | string match -rv '^$')
end

# Append new rate (as integer for spark)
set -l rate_int (math --scale=0 "$rate")
set -a rates $rate_int

# Trim to max_points
if test (count $rates) -gt $max_points
    set rates $rates[(math (count $rates) - $max_points + 1)..-1]
end

# Write history back
printf "%s\n" $rates > $history_file

# Pad with zeros if we don't have enough points yet
set -l padded
set -l pad_count (math "$max_points - "(count $rates))
if test $pad_count -gt 0
    for i in (seq $pad_count)
        set -a padded 0
    end
end
set -a padded $rates

# Generate sparkline inline (spark.fish logic inlined to avoid autoload dependency)
printf "%s\n" $padded | awk -v min="0" '
    {
        m = min == "" ? m == "" ? $0 : m > $0 ? $0 : m : min
        M = M == "" ? $0 : M < $0 ? $0 : M
        nums[NR] = $0
    }
    END {
        n = split("▁ ▂ ▃ ▄ ▅ ▆ ▇ █", sparks, " ") - 1
        while (++i <= NR)
            printf("%s", sparks[(M == m) ? 3 : sprintf("%.f", (1 + (nums[i] - m) * n / (M - m)))])
    }
' && echo

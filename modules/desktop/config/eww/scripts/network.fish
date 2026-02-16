#!/usr/bin/env fish

# Network stats script for eww
# Usage: network.fish [up|down|interface|status]

set -l interface (ip route | grep default | awk '{print $5}' | head -n1)

if test -z "$interface"
    # No default route, check for any active interface
    set interface (ip link show | grep "state UP" | grep -v "lo:" | head -n1 | awk -F: '{print $2}' | string trim)
end

if test -z "$interface"
    # Still no interface found, fallback
    set interface "lo"
end

# Handle interface and status queries early (no stats needed)
if test "$argv[1]" = "interface"
    echo $interface
    exit 0
else if test "$argv[1]" = "status"
    if ip link show $interface | grep -q "state UP"
        echo "up"
    else
        echo "down"
    end
    exit 0
end

# Read current stats
set -l rx_bytes_file "/sys/class/net/$interface/statistics/rx_bytes"
set -l tx_bytes_file "/sys/class/net/$interface/statistics/tx_bytes"

if test -f $rx_bytes_file -a -f $tx_bytes_file
    set -l rx_bytes (cat $rx_bytes_file)
    set -l tx_bytes (cat $tx_bytes_file)
    
    # Cache file locations
    set -l cache_dir "/tmp/eww-network-$USER"
    mkdir -p $cache_dir
    set -l rx_cache "$cache_dir/rx_bytes"
    set -l tx_cache "$cache_dir/tx_bytes"
    set -l time_cache "$cache_dir/time"
    
    set -l current_time (date +%s)
    
    if test -f $rx_cache -a -f $tx_cache -a -f $time_cache
        set -l old_rx (cat $rx_cache)
        set -l old_tx (cat $tx_cache)
        set -l old_time (cat $time_cache)
        
        set -l time_diff (math "$current_time - $old_time")
        
        if test $time_diff -gt 0
            set -l rx_diff (math "$rx_bytes - $old_rx")
            set -l tx_diff (math "$tx_bytes - $old_tx")
            
            set -l rx_rate (math "$rx_diff / $time_diff")
            set -l tx_rate (math "$tx_diff / $time_diff")
            
            if test "$argv[1]" = "down"
                # Download rate in KB/s
                printf "%.1f" (math "$rx_rate / 1024")
            else if test "$argv[1]" = "up"
                # Upload rate in KB/s
                printf "%.1f" (math "$tx_rate / 1024")
            else
                # Default: return download rate
                printf "%.1f" (math "$rx_rate / 1024")
            end
        else
            echo "0.0"
        end
    else
        # First run, initialize cache
        echo "0.0"
    end
    
    # Update cache
    echo $rx_bytes > $rx_cache
    echo $tx_bytes > $tx_cache
    echo $current_time > $time_cache
else
    echo "0.0"
end

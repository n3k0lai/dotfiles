#!/usr/bin/env fish

# Get memory usage percentage
set mem_usage (free | grep Mem | awk '{print ($3/$2) * 100.0}')

# Round to integer
printf "%.0f" $mem_usage

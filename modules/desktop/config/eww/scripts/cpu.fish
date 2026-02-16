#!/usr/bin/env fish

# Get CPU usage percentage
set cpu_usage (top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')

# Round to integer
printf "%.0f" $cpu_usage

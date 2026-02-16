#!/usr/bin/env fish

# Get GPU usage percentage (assuming NVIDIA)
# For AMD, you might need to adjust this command
set gpu_usage (nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null)

# If nvidia-smi fails, try AMD alternative or return 0
if test $status -ne 0
    # For AMD GPUs, you might use: rocm-smi --showuse | grep -A 1 "GPU" | tail -1 | awk '{print $7}' | tr -d '%'
    # But for now, return 0 if not available
    set gpu_usage 0
end

# Ensure it's a number and round to integer
printf "%.0f" $gpu_usage
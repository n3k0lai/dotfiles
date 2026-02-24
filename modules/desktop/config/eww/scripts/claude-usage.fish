#!/usr/bin/env fish

# Claude usage tracker for eww sidebar
# Queries OpenClaw gateway over Tailscale for session stats
# and probes Anthropic rate limit headers for plan usage
#
# Usage: claude-usage.fish [session|weekly|extra|all]
# Default: all (returns JSON for eww)

set -l mode $argv[1]
test -z "$mode"; and set mode "all"

set -l gateway "http://ene-1.bushbaby-mercat.ts.net:18789"
set -l token "389596fcdc3204b9e523d1db03608b94ab09e4b4e6df0242"
set -l cache_file "/tmp/claude-usage-cache.json"
set -l cache_max_age 30  # seconds

# Check cache freshness
if test -f "$cache_file"
    set -l cache_age (math (date +%s) - (stat -c %Y "$cache_file" 2>/dev/null; or echo 0))
    if test $cache_age -lt $cache_max_age
        switch $mode
            case session
                jq -r '.session_pct' "$cache_file" 2>/dev/null; or echo "0"
            case weekly
                jq -r '.weekly_pct' "$cache_file" 2>/dev/null; or echo "0"
            case extra
                jq -r '.extra_spent' "$cache_file" 2>/dev/null; or echo "0"
            case reset
                jq -r '.weekly_reset' "$cache_file" 2>/dev/null; or echo "?"
            case all
                cat "$cache_file"
        end
        return 0
    end
end

# Query OpenClaw gateway for session info
set -l gw_data (curl -s --connect-timeout 3 -H "Authorization: Bearer $token" "$gateway/api/status" 2>/dev/null)

# Parse session context from gateway (fallback values if unavailable)
set -l context_pct 0
set -l session_tokens 0
if test -n "$gw_data"
    set context_pct (echo "$gw_data" | jq -r '.context.percentUsed // 0' 2>/dev/null; or echo 0)
    set session_tokens (echo "$gw_data" | jq -r '.context.totalTokens // 0' 2>/dev/null; or echo 0)
end

# Probe Anthropic for rate limit headers using minimal API call
# Uses the key from the OpenClaw env
set -l anthropic_key (ssh -o ConnectTimeout=2 ene-1 'cat /proc/(pgrep -f openclaw-gate -o)/environ 2>/dev/null | tr "\\0" "\\n" | grep ANTHROPIC_API_KEY | cut -d= -f2' 2>/dev/null)

set -l session_pct 0
set -l weekly_pct 0
set -l weekly_reset "?"
set -l extra_spent "0"

if test -n "$anthropic_key"
    # Make a minimal count_tokens request to get rate limit headers
    set -l headers (curl -s -D - -o /dev/null --connect-timeout 5 \
        -H "x-api-key: $anthropic_key" \
        -H "anthropic-version: 2023-06-01" \
        -H "content-type: application/json" \
        -d '{"model":"claude-sonnet-4-20250514","messages":[{"role":"user","content":"hi"}],"max_tokens":1}' \
        "https://api.anthropic.com/v1/messages" 2>/dev/null)

    # Parse rate limit headers
    # Session limits
    set -l session_limit (echo "$headers" | grep -i "anthropic-ratelimit-tokens-limit" | head -1 | awk '{print $2}' | tr -d '\r')
    set -l session_remaining (echo "$headers" | grep -i "anthropic-ratelimit-tokens-remaining" | head -1 | awk '{print $2}' | tr -d '\r')
    set -l session_reset_raw (echo "$headers" | grep -i "anthropic-ratelimit-tokens-reset" | head -1 | awk '{print $2}' | tr -d '\r')

    if test -n "$session_limit" -a -n "$session_remaining"
        set -l used (math $session_limit - $session_remaining)
        set session_pct (math --scale=0 "($used / $session_limit) * 100")
    end

    # Weekly/request limits (if exposed)
    set -l req_limit (echo "$headers" | grep -i "anthropic-ratelimit-requests-limit" | head -1 | awk '{print $2}' | tr -d '\r')
    set -l req_remaining (echo "$headers" | grep -i "anthropic-ratelimit-requests-remaining" | head -1 | awk '{print $2}' | tr -d '\r')

    if test -n "$req_limit" -a -n "$req_remaining"
        set -l req_used (math $req_limit - $req_remaining)
        set weekly_pct (math --scale=0 "($req_used / $req_limit) * 100")
    end

    # Parse reset time
    if test -n "$session_reset_raw"
        # ISO 8601 → human readable
        set -l reset_epoch (date -d "$session_reset_raw" +%s 2>/dev/null; or echo 0)
        set -l now_epoch (date +%s)
        set -l diff (math $reset_epoch - $now_epoch)
        if test $diff -gt 3600
            set weekly_reset (math --scale=0 "$diff / 3600")"h"
        else if test $diff -gt 60
            set weekly_reset (math --scale=0 "$diff / 60")"m"
        else
            set weekly_reset "now"
        end
    end
end

# Determine status color class
set -l status "ok"
if test $session_pct -ge 90; or test $weekly_pct -ge 90
    set status "critical"
else if test $session_pct -ge 70; or test $weekly_pct -ge 70
    set status "warning"
end

# Build JSON and cache it
set -l json "{\"session_pct\": $session_pct, \"weekly_pct\": $weekly_pct, \"extra_spent\": \"$extra_spent\", \"weekly_reset\": \"$weekly_reset\", \"context_pct\": $context_pct, \"session_tokens\": $session_tokens, \"status\": \"$status\"}"

echo "$json" > "$cache_file"

switch $mode
    case session
        echo "$session_pct"
    case weekly
        echo "$weekly_pct"
    case extra
        echo "$extra_spent"
    case reset
        echo "$weekly_reset"
    case status
        echo "$status"
    case all
        echo "$json"
end

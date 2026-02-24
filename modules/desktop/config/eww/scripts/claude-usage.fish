#!/usr/bin/env fish

# Claude usage tracker for eww sidebar
# Probes Anthropic rate limit headers from a minimal API call
#
# Usage: claude-usage.fish [session|weekly|reset|status|all]

set -l mode $argv[1]
test -z "$mode"; and set mode "all"

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
            case reset
                jq -r '.weekly_reset' "$cache_file" 2>/dev/null; or echo "?"
            case status
                jq -r '.status' "$cache_file" 2>/dev/null; or echo "ok"
            case all
                cat "$cache_file"
        end
        return 0
    end
end

# Read API key from local env file or environment
set -l anthropic_key ""
if test -n "$ANTHROPIC_API_KEY"
    set anthropic_key "$ANTHROPIC_API_KEY"
else if test -f "$HOME/.config/anthropic.env"
    set anthropic_key (grep ANTHROPIC_API_KEY "$HOME/.config/anthropic.env" | cut -d= -f2 | tr -d '"' | tr -d "'" | string trim)
else if test -f /run/agenix/openclaw-env
    set anthropic_key (grep ANTHROPIC_API_KEY /run/agenix/openclaw-env 2>/dev/null | cut -d= -f2 | string trim)
end

set -l session_pct 0
set -l weekly_pct 0
set -l weekly_reset "?"

if test -n "$anthropic_key"
    # Minimal API call to get rate limit headers
    set -l headers (curl -s -D - -o /dev/null --connect-timeout 5 \
        -H "x-api-key: $anthropic_key" \
        -H "anthropic-version: 2023-06-01" \
        -H "content-type: application/json" \
        -d '{"model":"claude-sonnet-4-20250514","messages":[{"role":"user","content":"hi"}],"max_tokens":1}' \
        "https://api.anthropic.com/v1/messages" 2>/dev/null)

    # Parse rate limit headers
    set -l token_limit (echo "$headers" | grep -i "anthropic-ratelimit-tokens-limit" | head -1 | awk '{print $2}' | tr -d '\r')
    set -l token_remaining (echo "$headers" | grep -i "anthropic-ratelimit-tokens-remaining" | head -1 | awk '{print $2}' | tr -d '\r')
    set -l reset_time (echo "$headers" | grep -i "anthropic-ratelimit-tokens-reset" | head -1 | awk '{print $2}' | tr -d '\r')

    # Request-level limits (may indicate weekly)
    set -l req_limit (echo "$headers" | grep -i "anthropic-ratelimit-requests-limit" | head -1 | awk '{print $2}' | tr -d '\r')
    set -l req_remaining (echo "$headers" | grep -i "anthropic-ratelimit-requests-remaining" | head -1 | awk '{print $2}' | tr -d '\r')

    # Session token usage
    if test -n "$token_limit" -a -n "$token_remaining" -a "$token_limit" != "0"
        set -l used (math "$token_limit - $token_remaining")
        set session_pct (math --scale=0 "($used / $token_limit) * 100")
    end

    # Request usage (proxy for weekly)
    if test -n "$req_limit" -a -n "$req_remaining" -a "$req_limit" != "0"
        set -l req_used (math "$req_limit - $req_remaining")
        set weekly_pct (math --scale=0 "($req_used / $req_limit) * 100")
    end

    # Parse reset time
    if test -n "$reset_time"
        set -l reset_epoch (date -d "$reset_time" +%s 2>/dev/null)
        if test -n "$reset_epoch"
            set -l now_epoch (date +%s)
            set -l diff (math "$reset_epoch - $now_epoch")
            if test $diff -gt 3600
                set weekly_reset (math --scale=0 "$diff / 3600")"h"
            else if test $diff -gt 60
                set weekly_reset (math --scale=0 "$diff / 60")"m"
            else if test $diff -gt 0
                set weekly_reset "now"
            end
        end
    end
end

# Determine status
set -l status "ok"
if test $session_pct -ge 90; or test $weekly_pct -ge 90
    set status "critical"
else if test $session_pct -ge 70; or test $weekly_pct -ge 70
    set status "warning"
end

# Build JSON and cache
set -l json "{\"session_pct\": $session_pct, \"weekly_pct\": $weekly_pct, \"weekly_reset\": \"$weekly_reset\", \"status\": \"$status\"}"
echo "$json" > "$cache_file"

switch $mode
    case session
        echo "$session_pct"
    case weekly
        echo "$weekly_pct"
    case reset
        echo "$weekly_reset"
    case status
        echo "$status"
    case all
        echo "$json"
end

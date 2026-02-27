#!/usr/bin/env fish

# Claude usage tracker for eww sidebar
# Reads from claude.ai usage API (five_hour / seven_day utilization)
#
# Requires in ~/.config/anthropic.env:
#   CLAUDE_SESSION_KEY=sk-ant-sid01-...  (from claude.ai browser cookies, expires ~30 days)
#   CLAUDE_ORG_ID=...                    (from the API URL on claude.ai/settings/usage)
#
# Usage: claude-usage.fish [session|weekly|reset|status|all]

set -l mode $argv[1]
test -z "$mode"; and set mode "all"

set -l cache_file "/tmp/claude-usage-cache.json"
set -l cache_max_age 60  # seconds

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
                jq -r '.reset' "$cache_file" 2>/dev/null; or echo "?"
            case status
                jq -r '.status' "$cache_file" 2>/dev/null; or echo "ok"
            case context
                echo "0"
            case all
                cat "$cache_file"
        end
        return 0
    end
end

# Read credentials
set -l session_key ""
set -l org_id ""

if test -f "$HOME/.config/anthropic.env"
    set session_key (grep CLAUDE_SESSION_KEY "$HOME/.config/anthropic.env" | cut -d= -f2- | string trim)
    set org_id (grep CLAUDE_ORG_ID "$HOME/.config/anthropic.env" | cut -d= -f2- | string trim)
end

set -l session_pct 0
set -l weekly_pct 0
set -l weekly_reset "?"

if test -n "$org_id"
    # Extract all claude.ai cookies from Firefox (bypasses Cloudflare bot protection)
    # Use find instead of glob to avoid fish wildcard errors when path doesn't exist
    set -l ff_profile (find ~/.mozilla/firefox -maxdepth 1 -name "*.default*" -type d 2>/dev/null | sort -r | head -1)
    set -l cookie_str ""
    if test -n "$ff_profile" -a -f "$ff_profile/cookies.sqlite"
        set -l tmp_db "/tmp/eww-claude-cookies.sqlite"
        cp "$ff_profile/cookies.sqlite" "$tmp_db" 2>/dev/null
        set cookie_str (sqlite3 "$tmp_db" \
            "SELECT name || '=' || value FROM moz_cookies WHERE host LIKE '%claude.ai';" 2>/dev/null | \
            string join "; ")
    end
    # Fall back to just sessionKey if Firefox cookies unavailable
    if test -z "$cookie_str" -a -n "$session_key"
        set cookie_str "sessionKey=$session_key"
    end

    # curl-impersonate-ff mimics Firefox's TLS fingerprint, required to pass Cloudflare
    set -l response (string join \n (curl-impersonate-ff -s --connect-timeout 5 \
        -H "Cookie: $cookie_str" \
        -H "Content-Type: application/json" \
        -H "anthropic-client-platform: web_claude_ai" \
        "https://claude.ai/api/organizations/$org_id/usage" 2>/dev/null))

    # Only parse if response is valid JSON
    if echo "$response" | jq . >/dev/null 2>/dev/null
        set session_pct (echo "$response" | jq -r '(.five_hour.utilization // 0) | floor')
        set weekly_pct (echo "$response" | jq -r '(.seven_day.utilization // 0) | floor')

        # Reset time from five_hour window
        set -l reset_iso (echo "$response" | jq -r '.five_hour.resets_at // ""')
        if test -n "$reset_iso"
            set -l reset_epoch (date -d "$reset_iso" +%s 2>/dev/null)
            if test -n "$reset_epoch"
                set -l diff (math "$reset_epoch - "(date +%s))
                if test $diff -gt 3600
                    set weekly_reset (math --scale=0 "$diff / 3600")"h"(math --scale=0 "($diff % 3600) / 60")"m"
                else if test $diff -gt 60
                    set weekly_reset (math --scale=0 "$diff / 60")"m"
                else if test $diff -gt 0
                    set weekly_reset "<1m"
                end
            end
        end
    end
end

# Determine status
set -l usage_status "ok"
if test $session_pct -ge 90; or test $weekly_pct -ge 90
    set usage_status "critical"
else if test $session_pct -ge 70; or test $weekly_pct -ge 70
    set usage_status "warning"
end

# Cache and output
set -l json "{\"session_pct\": $session_pct, \"weekly_pct\": $weekly_pct, \"reset\": \"$weekly_reset\", \"status\": \"$usage_status\"}"
echo "$json" > "$cache_file"

switch $mode
    case session
        echo "$session_pct"
    case weekly
        echo "$weekly_pct"
    case reset
        echo "$weekly_reset"
    case status
        echo "$usage_status"
    case context
        echo "0"
    case all
        echo "$json"
end

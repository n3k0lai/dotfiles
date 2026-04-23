#!/usr/bin/env fish

# Ene Sync - Export Discord DMs and sync to Ene Memory Core
# Usage: ene-sync [full|recent]
#   full   - Export all messages (first run)
#   recent - Export only messages since last sync (default)

function ene-sync
    # Config
    set -l ENE_DM_CHANNEL_ID "1473005603432562925"
    set -l ENE_SERVER_URL $ENE_SERVER_URL
    set -l EXPORT_DIR "$HOME/.cache/ene-sync"
    set -l STATE_FILE "$HOME/.cache/ene-sync/last-sync"

    if test -z "$ENE_SERVER_URL"
        echo "Error: ENE_SERVER_URL not set. Set it in your environment."
        return 1
    end

    # Get Discord token from environment or 1password
    set -l DISCORD_TOKEN $DISCORD_TOKEN
    if test -z "$DISCORD_TOKEN"
        # Try to get from 1password if available
        if command -q op
            set DISCORD_TOKEN (op read "op://Private/Discord/token" 2>/dev/null)
        end
    end

    if test -z "$DISCORD_TOKEN"
        echo "Error: DISCORD_TOKEN not set. Set it in environment or 1Password."
        return 1
    end

    # Ensure export directory exists
    mkdir -p $EXPORT_DIR

    # Determine mode
    set -l MODE $argv[1]
    if test -z "$MODE"
        set MODE "recent"
    end

    # Build export command
    set -l EXPORT_CMD "DiscordChatExporter.Cli export"
    set -l EXPORT_FILE "$EXPORT_DIR/ene-dms.json"

    # Base options
    set -a EXPORT_CMD "-t" "$DISCORD_TOKEN"
    set -a EXPORT_CMD "-c" "$ENE_DM_CHANNEL_ID"
    set -a EXPORT_CMD "-f" "Json"
    set -a EXPORT_CMD "-o" "$EXPORT_FILE"
    # Only export our conversation, skip bot spam
    set -a EXPORT_CMD "--filter" "from:n3k0lai | from:ene"

    # Add date filter for incremental sync
    if test "$MODE" = "recent" -a -f "$STATE_FILE"
        set -l LAST_SYNC (cat $STATE_FILE)
        if test -n "$LAST_SYNC"
            # Add 1 second to avoid re-exporting the last message
            set -l AFTER_DATE (date -d "$LAST_SYNC + 1 second" "+%Y-%m-%d %H:%M:%S" 2>/dev/null)
            if test -n "$AFTER_DATE"
                set -a EXPORT_CMD "--after" "$AFTER_DATE"
                echo "Exporting messages after: $AFTER_DATE"
            end
        end
    else
        echo "Exporting all messages (full sync)..."
    end

    # Run export
    echo "Running: $EXPORT_CMD"
    eval $EXPORT_CMD

    if test $status -ne 0
        echo "Error: Export failed"
        return 1
    end

    # Check if file was created and has content
    if not test -f "$EXPORT_FILE"
        echo "Error: Export file not created"
        return 1
    end

    set -l FILE_SIZE (stat -c%s "$EXPORT_FILE" 2>/dev/null)
    if test "$FILE_SIZE" = "0" -o -z "$FILE_SIZE"
        echo "No new messages to sync"
        rm -f "$EXPORT_FILE"
        return 0
    end

    echo "Exported $FILE_SIZE bytes"

    # Send to Ene server
    echo "Sending to Ene Memory Core..."
    set -l HTTP_RESPONSE (curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        --data-binary "@$EXPORT_FILE" \
        "$ENE_SERVER_URL/ingest" 2>&1)

    set -l CURL_STATUS $status
    set -l HTTP_CODE (echo "$HTTP_RESPONSE" | tail -n1)
    set -l RESPONSE_BODY (echo "$HTTP_RESPONSE" | head -n-1)

    if test $CURL_STATUS -ne 0
        echo "Error: Failed to connect to Ene server"
        echo "Curl error: $HTTP_RESPONSE"
        return 1
    end

    if test "$HTTP_CODE" = "200"
        # Update last sync timestamp
        date -Iseconds > "$STATE_FILE"
        echo "Sync complete!"
        echo "$RESPONSE_BODY" | jq -r '.output' 2>/dev/null || echo "$RESPONSE_BODY"
        # Clean up
        rm -f "$EXPORT_FILE"
        return 0
    else
        echo "Error: Server returned HTTP $HTTP_CODE"
        echo "$RESPONSE_BODY" | jq . 2>/dev/null || echo "$RESPONSE_BODY"
        return 1
    end
end

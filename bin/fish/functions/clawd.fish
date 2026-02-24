# openclaw gateway helper — status, logs, and safe restart
function clawd --argument-names cmd
    set -l service "openclaw-gateway"

    switch "$cmd"
        case status st s ""
            # Show service status + running process info
            echo "🐾 OpenClaw Gateway Status"
            echo ""

            # systemd service
            set -l active (systemctl is-active $service 2>/dev/null)
            set -l pid (systemctl show $service -p MainPID --value 2>/dev/null)
            echo "  systemd: $active (pid $pid)"

            # check for rogue processes outside systemd
            set -l all_pids (pgrep -f "openclaw-gateway" 2>/dev/null)
            if test (count $all_pids) -gt 1
                echo "  ⚠️  MULTIPLE PROCESSES DETECTED: $all_pids"
                echo "  This causes port conflicts. Run: clawd fix"
            else if test (count $all_pids) -eq 1
                if test "$all_pids[1]" != "$pid"
                    echo "  ⚠️  ROGUE PROCESS: pid $all_pids[1] (not managed by systemd)"
                    echo "  Run: clawd fix"
                else
                    echo "  ✅ single process, systemd-managed"
                end
            else
                echo "  ❌ no gateway process found"
            end

            # port check
            echo ""
            set -l port_pid (ss -tlnp 2>/dev/null | grep ":18789" | string match -r 'pid=(\d+)' | tail -1)
            if test -n "$port_pid"
                echo "  port 18789: held by pid $port_pid"
            else
                echo "  port 18789: free"
            end

            # env check (verify secrets are loaded)
            if test -n "$pid" -a "$pid" != "0"
                set -l has_gemini (cat /proc/$pid/environ 2>/dev/null | tr '\0' '\n' | grep -c GEMINI_API_KEY)
                set -l has_gog (cat /proc/$pid/environ 2>/dev/null | tr '\0' '\n' | grep -c GOG_ACCOUNT)
                echo ""
                echo "  secrets: GEMINI_API_KEY="(test $has_gemini -gt 0; and echo "✅"; or echo "❌")" GOG_ACCOUNT="(test $has_gog -gt 0; and echo "✅"; or echo "❌")
            end

        case logs l
            journalctl -u $service -f --no-pager

        case restart r
            echo "🔄 Restarting gateway via systemd (preserves agenix secrets)..."
            sudo systemctl restart $service
            sleep 3
            clawd status

        case fix f
            echo "🔧 Fixing gateway process conflicts..."
            # Kill everything, let systemd restart cleanly
            echo "  stopping systemd service..."
            sudo systemctl stop $service 2>/dev/null
            sleep 1
            echo "  killing any remaining openclaw processes..."
            pkill -f "openclaw-gateway" 2>/dev/null
            sleep 2
            echo "  starting systemd service..."
            sudo systemctl start $service
            sleep 5
            clawd status

        case help h
            echo "clawd - OpenClaw gateway management"
            echo ""
            echo "  clawd              show status (default)"
            echo "  clawd status|st    show status + process health"
            echo "  clawd logs|l       follow journal logs"
            echo "  clawd restart|r    safe restart via systemd"
            echo "  clawd fix|f        kill rogues + clean restart"
            echo "  clawd help|h       this help"
            echo ""
            echo "  ⚠️  NEVER use 'openclaw gateway restart' — it bypasses systemd"
            echo "  and won't load agenix secrets (GEMINI_API_KEY, GOG, etc)."
            echo "  Always use 'clawd restart' or 'sudo systemctl restart $service'."

        case "*"
            echo "unknown command: $cmd (try: clawd help)"
            return 1
    end
end

# league - Launch League of Legends via Moonlight (streamed from Windows Sunshine host)
function league --description "Launch Moonlight to stream League from Windows host"
    if not command -q moonlight
        echo "league: moonlight-qt not found (enable modules.gaming.riot)"
        return 1
    end

    if set -q RIOT_HOST
        echo "Opening Moonlight → $RIOT_HOST"
        moonlight stream $RIOT_HOST
    else
        echo "Opening Moonlight (pair with Windows Sunshine host if first run)"
        moonlight &
    end
end
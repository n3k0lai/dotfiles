# ene-yt-transcripts — fetch YouTube captions on kiss, upload to Hermes on ene
#
# Usage:
#   ene-yt-transcripts VIDEO_ID_OR_URL
#   ene-yt-transcripts @SumitoMedia --limit 5
#   ene-yt-transcripts sumito --limit 3
#
# Requires: nix-shell, ssh/scp to nicho@ene, Firefox logged into YouTube

function ene-yt-transcripts --description "Fetch YouTube VTT on kiss → Hermes audit dir on ene"
    set -l ENE_HOST (test -n "$ENE_HOST"; and echo "$ENE_HOST"; or echo "ene")
    set -l ENE_USER (test -n "$ENE_USER"; and echo "$ENE_USER"; or echo "nicho")
    set -l ENE_DEST "/var/lib/hermes/.hermes/x-context/audits/youtube"
    set -l YTDLP_COOKIES_BROWSER (test -n "$YTDLP_COOKIES"; and echo "$YTDLP_COOKIES"; or echo "firefox")
    set -l LIMIT 5
    set -l DRY_RUN 0
    set -l TARGET ""
    set -l COOKIES_OUT ""

    set -l i 1
    while test $i -le (count $argv)
        switch $argv[$i]
            case -l --limit
                set i (math $i + 1)
                set LIMIT $argv[$i]
            case -c --cookies
                set i (math $i + 1)
                set YTDLP_COOKIES_BROWSER $argv[$i]
            case --cookies-out
                set i (math $i + 1)
                set COOKIES_OUT $argv[$i]
            case --host
                set i (math $i + 1)
                set ENE_HOST $argv[$i]
            case -n --dry-run
                set DRY_RUN 1
            case -h --help
                _ene_yt_transcripts_help
                return 0
            case '-*'
                echo "ene-yt-transcripts: unknown option $argv[$i]"
                _ene_yt_transcripts_help
                return 1
            case '*'
                if test -z "$TARGET"
                    set TARGET $argv[$i]
                else
                    echo "ene-yt-transcripts: unexpected argument $argv[$i]"
                    return 1
                end
        end
        set i (math $i + 1)
    end

    if test -z "$TARGET"
        _ene_yt_transcripts_help
        return 1
    end

    # Influencer alias → @handle
    switch $TARGET
        case sumito sumitomedia
            set TARGET "@SumitoMedia"
    end

    set -l VIDEO_IDS
    if _ene_yt_is_video_ref "$TARGET"
        set VIDEO_IDS (_ene_yt_extract_video_id "$TARGET")
    else
        set -l channel_ref "$TARGET"
        if not string match -q '@*' "$channel_ref"
            set channel_ref "@$channel_ref"
        end
        set VIDEO_IDS (_ene_yt_list_channel_ids "$channel_ref" $LIMIT "$YTDLP_COOKIES_BROWSER")
        if test $status -ne 0 -o (count $VIDEO_IDS) -eq 0
            echo "ene-yt-transcripts: no videos found for $channel_ref"
            return 1
        end
    end

    echo "ene-yt-transcripts: uploading "(count $VIDEO_IDS)" transcript(s) → $ENE_USER@$ENE_HOST:$ENE_DEST"

    set -l UPLOADED
    set -l FAILED
    set -l WORK (mktemp -d)
    trap "rm -rf $WORK" EXIT

    for vid in $VIDEO_IDS
        set -l local_vtt "$WORK/$vid.vtt"
        if test $DRY_RUN -eq 1
            echo "  [dry-run] would fetch $vid"
            continue
        end

        echo "  fetching $vid …"
        if not _ene_yt_fetch_vtt "$vid" "$local_vtt" "$YTDLP_COOKIES_BROWSER"
            echo "  ✗ fetch failed: $vid"
            set -a FAILED $vid
            continue
        end

        if not test -s "$local_vtt"
            echo "  ✗ empty transcript: $vid"
            set -a FAILED $vid
            continue
        end

        set -l remote_tmp "/tmp/yt-audit-$vid.vtt"
        if not scp -q "$local_vtt" "$ENE_USER@$ENE_HOST:$remote_tmp"
            echo "  ✗ scp failed: $vid"
            set -a FAILED $vid
            continue
        end

        ssh -q "$ENE_USER@$ENE_HOST" \
            "sudo mkdir -p '$ENE_DEST' && \
             sudo cp '$remote_tmp' '$ENE_DEST/$vid.vtt' && \
             sudo chown hermes:hermes '$ENE_DEST' '$ENE_DEST/$vid.vtt' && \
             rm -f '$remote_tmp'"

        if test $status -ne 0
            echo "  ✗ remote install failed: $vid"
            set -a FAILED $vid
            continue
        end

        set -l bytes (stat -c%s "$local_vtt" 2>/dev/null)
        echo "  ✓ $vid ($bytes bytes) → $ENE_DEST/$vid.vtt"
        set -a UPLOADED $vid
    end

    # Optional: also export + upload a cookies.txt for direct yt-dlp use on ene (avoids repeated kiss fetches for metadata).
    # Uses the new refresh_yt_cookies.py (supports --from-firefox or expects prior browser_cdp via Hermes).
    # This is the modern path leveraging nous portal Browser Use / local /browser connect + CDP Network.getAllCookies.
    if test -n "$COOKIES_OUT"; and test (count $UPLOADED) -gt 0
        set -l cookies_local "$WORK/youtube-cookies.txt"
        set -l refresh_py "python3 skills/influencer/youtube-audit/scripts/refresh_yt_cookies.py"
        if type -q python3; and test -f "skills/influencer/youtube-audit/scripts/refresh_yt_cookies.py"
            echo "  exporting cookies via refresh_yt_cookies.py --from-firefox ..."
            $refresh_py --from-firefox --out "$cookies_local" --test 2>&1 | tail -5
        else
            echo "  (refresh_yt_cookies.py not found in tree; falling back to note only)"
            echo "  Use Hermes on this machine with browser tools (or /browser connect) + browser_cdp(Network.getAllCookies) then feed to the script."
        end
        if test -s "$cookies_local"
            set -l remote_cookies "$ENE_DEST/cookies.txt"
            scp -q "$cookies_local" "$ENE_USER@$ENE_HOST:/tmp/yt-cookies.$$" && \
            ssh -q "$ENE_USER@$ENE_HOST" "sudo mkdir -p '$ENE_DEST' && sudo cp '/tmp/yt-cookies.$$' '$remote_cookies' && sudo chown hermes:hermes '$remote_cookies' && rm -f '/tmp/yt-cookies.$$'"
            if test $status -eq 0
                echo "  ✓ cookies.txt → $remote_cookies"
            end
        end
    end

    if test $DRY_RUN -eq 1
        return 0
    end

    if test (count $UPLOADED) -gt 0
        set -l now (date -u +%Y-%m-%dT%H:%M:%SZ)
        set -l json_ids (_ene_yt_json_ids $UPLOADED)
        set -l manifest_json "{\"uploaded_at\":\"$now\",\"video_ids\":[$json_ids],\"source\":\"kiss/ene-yt-transcripts\"}"
        printf '%s' "$manifest_json" | ssh -q "$ENE_USER@$ENE_HOST" \
            "sudo tee '$ENE_DEST/manifest.json' >/dev/null && sudo chown hermes:hermes '$ENE_DEST/manifest.json'"
        echo ""
        echo "Done: "(count $UPLOADED)" uploaded, "(count $FAILED)" failed"
        echo "Hermes ingest:"
        for vid in $UPLOADED
            echo "  python3 skills/influencer/youtube-audit/scripts/ingest.py $vid --transcript-file x-context/audits/youtube/$vid.vtt"
        end
        if test -n "$COOKIES_OUT"
            echo "  (with cookies for better metadata on ene):"
            echo "  python3 skills/influencer/youtube-audit/scripts/ingest.py ... --cookies-file x-context/audits/youtube/cookies.txt"
            echo "  # or set YTDLP_COOKIES_FILE before running ingest / yt-dlp"
        end
    else
        echo "ene-yt-transcripts: nothing uploaded"
        return 1
    end
end

function _ene_yt_transcripts_help
    echo "ene-yt-transcripts — kiss → ene YouTube caption transfer"
    echo ""
    echo "Usage:"
    echo "  ene-yt-transcripts VIDEO_ID_OR_URL"
    echo "  ene-yt-transcripts @ChannelHandle --limit 5"
    echo "  ene-yt-transcripts sumito --limit 3"
    echo ""
    echo "Options:"
    echo "  -l, --limit N       Channel mode: recent N videos (default 5)"
    echo "  -c, --cookies B     yt-dlp browser for cookies (default: firefox)"
    echo "  --cookies-out       Also export a Netscape cookies.txt (via refresh_yt_cookies.py --from-firefox or browser tools) and upload to ene as cookies.txt"
    echo "  --host HOST         SSH host (default: ene, or \$ENE_HOST)"
    echo "  -n, --dry-run       List targets only"
    echo ""
    echo "Env: ENE_HOST, ENE_USER (default nicho), YTDLP_COOKIES"
    echo "Dest: /var/lib/hermes/.hermes/x-context/audits/youtube/"
    echo "See skills/influencer/youtube-audit/scripts/refresh_yt_cookies.py and SKILL.md for browser-use / CDP (nous portal) cookie extraction."
end

function _ene_yt_is_video_ref --argument-names ref
    if string match -qr '^[A-Za-z0-9_-]{11}$' "$ref"
        return 0
    end
    if string match -q '*youtube.com*' "$ref"; or string match -q '*youtu.be*' "$ref"
        return 0
    end
    return 1
end

function _ene_yt_extract_video_id --argument-names ref
    if string match -qr '^[A-Za-z0-9_-]{11}$' "$ref"
        echo $ref
        return 0
    end
    set -l id (string replace -r '.*(?:v=|youtu\.be/|shorts/|embed/|live/)([A-Za-z0-9_-]{11}).*' '$1' "$ref")
    if string match -qr '^[A-Za-z0-9_-]{11}$' "$id"
        echo $id
        return 0
    end
    return 1
end

function _ene_yt_list_channel_ids --argument-names channel_ref limit cookies_browser
    set -l handle (string replace -r '^@' '' "$channel_ref")
    set -l url "https://www.youtube.com/@$handle/videos"
    nix-shell -p yt-dlp deno --run \
        "yt-dlp --no-update --cookies-from-browser $cookies_browser --flat-playlist --print '%(id)s' --playlist-end $limit '$url'" \
        2>/dev/null
end

function _ene_yt_fetch_vtt --argument-names video_id out_path cookies_browser
    set -l url "https://www.youtube.com/watch?v=$video_id"
    set -l stem (string replace -r '\.vtt$' '' "$out_path")
    nix-shell -p yt-dlp deno --run \
        "yt-dlp --no-update --cookies-from-browser $cookies_browser \
         --ignore-no-formats-error --write-auto-sub --write-sub --sub-lang en \
         --skip-download --sub-format vtt -o '$stem' '$url'" \
        2>/dev/null
    # yt-dlp writes stem.en.vtt (or stem.vtt depending on version)
    if test -f "$stem.en.vtt"
        mv -f "$stem.en.vtt" "$out_path"
    else if test -f "$stem.vtt"
        mv -f "$stem.vtt" "$out_path"
    end
    test -s "$out_path"
end

function _ene_yt_json_ids --argument-names ids
    set -l parts
    for id in $ids
        set -a parts "\"$id\""
    end
    string join ',' $parts
end
# fdroid-repo inbox pickup. Runs as the fdroid service user (no root).
#
# The inbox is a setgid dir (group fdroid-inbox, 2770) that the uploader
# (grokbot-ene, over SSH) writes into. The box uploads to hidden temp names
# (.<name>.partial) and renames them into place: the APK first, the manifest last:
#   <package>_<versionCode>.apk   then   <package>_<versionCode>.json
# A manifest means its APK is complete. Files are copied into incoming/ (so the
# fdroid user owns them) and the originals removed.
#
# Env: INBOX DATA_DIR
set -euo pipefail

[ -d "$INBOX" ] || exit 0
mkdir -p "$DATA_DIR/incoming" "$DATA_DIR/rejected"
name_re='^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+_[0-9]+\.(apk|json)$'

take() { # <inbox file>
  local f="$1" base
  base="$(basename "$f")"
  cp --no-preserve=mode,ownership "$f" "$DATA_DIR/incoming/$base.tmp"
  chmod 0640 "$DATA_DIR/incoming/$base.tmp"
  mv "$DATA_DIR/incoming/$base.tmp" "$DATA_DIR/incoming/$base"
  rm -f "$f"
}

# Uploads in progress are hidden (.<name>.partial). Drop ones abandoned for a day.
find "$INBOX" -maxdepth 1 -type f -name '.*' -mmin +1440 -print -delete || true

# Anything else that is not <pkg>_<vc>.apk/.json (or is a symlink) goes to rejected/.
find "$INBOX" -maxdepth 1 \( -type f -o -type l \) ! -name '.*' -print0 |
while IFS= read -r -d '' f; do
  base="$(basename "$f")"
  if [ -L "$f" ] || ! [[ "$base" =~ $name_re ]]; then
    echo "fdroid-repo: unexpected inbox file moved to rejected/: $base" >&2
    mv "$f" "$DATA_DIR/rejected/$(date +%Y%m%dT%H%M%S)-unexpected-$base"
  fi
done

find "$INBOX" -maxdepth 1 -type f -name '*.json' ! -name '.*' -print0 |
while IFS= read -r -d '' m; do
  apk="${m%.json}.apk"
  if [ -f "$apk" ]; then
    take "$apk"; take "$m"
  elif [ -f "$DATA_DIR/incoming/$(basename "$apk")" ]; then
    take "$m"
  elif [ -n "$(find "$m" -mmin +10)" ]; then
    take "$m"   # APK never came; ingest will reject the manifest.
  fi
done

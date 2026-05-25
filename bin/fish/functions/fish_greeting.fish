function fish_greeting
  # Ultra-fast path: if the system fortune(1) can find "chinese" in its default
  # search path (works on some linux setups via profile links), use it directly.
  # This is the cheapest possible and uses the compiled .dat index.
  if command -q fortune
    set -l out (fortune chinese 2>/dev/null)
    if test -n "$out"
      echo $out
      return
    end
  end

  # Fast path: explicit path baked by host config (e.g. waves.nix sets CHINESE_FORTUNE_FILE)
  # avoids any find cost on darwin and other configured hosts.
  set -l chinese_file "$CHINESE_FORTUNE_FILE"
  if test -z "$chinese_file" -o ! -f "$chinese_file"
    # Fast locate: only enumerate top-level /nix/store dirs matching *fortune* (tiny set),
    # then search inside them. Avoids the previous -maxdepth 5 full-tree scan which
    # caused multi-second delays on every new terminal/shell.
    set chinese_file ""
    for d in (find /nix/store -maxdepth 1 -name '*fortune*' -type d 2>/dev/null)
      for p in (find "$d" -name 'chinese' -type f 2>/dev/null | head -1)
        if test -n "$p"
          set chinese_file $p
          break
        end
      end
      if test -n "$chinese_file"
        break
      end
    end
  end
  if test -z "$chinese_file"
    # legacy fallback name pattern
    for d in (find /nix/store -maxdepth 1 -name '*fortunes*' -type d 2>/dev/null)
      for p in (find "$d" -name 'chinese' -type f 2>/dev/null | head -1)
        if test -n "$p"
          set chinese_file $p
          break
        end
      end
      if test -n "$chinese_file"
        break
      end
    end
  end

  if test -z "$chinese_file"
    return
  end

  # Try the real fortune(1) with explicit path. When the binary and its .dat
  # are compatible this is fast (uses index). On darwin the fortune binary
  # from nix cannot read the .dat (even one built for darwin), hence awk.
  if command -q fortune
    set -l out (fortune "$chinese_file" 2>/dev/null)
    if test -n "$out"
      echo $out
      return
    end
  end

  # Awk fallback (preserves original darwin support added for waves.nix).
  # Parses the raw 'chinese' fortune text (delimited by lines containing only '%').
  if command -q awk
    awk '
      BEGIN { srand() }
      NR == 1 { current = $0; next }
      /^%$/ {
        entries[n++] = current
        current = ""
        next
      }
      { current = current "\n" $0 }
      END {
        if (current != "") entries[n++] = current
        if (n > 0) print entries[int(rand() * n)]
      }
    ' "$chinese_file"
  end
end

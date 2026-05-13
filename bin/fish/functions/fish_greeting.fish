function fish_greeting
  if not command -q awk
    return
  end

  # Find the chinese fortune database in the nix store
  set chinese_file ""
  for p in (find /nix/store -maxdepth 5 -path '*fortune-with-zh*' -name 'chinese' -type f 2>/dev/null)
    set chinese_file $p
    break
  end
  if test -z "$chinese_file"
    for p in (find /nix/store -maxdepth 5 -path '*fortunes*' -name 'chinese' -type f 2>/dev/null)
      set chinese_file $p
      break
    end
  end

  if test -n "$chinese_file"
    # Use awk to pick exactly one random entry.
    # Fortune format: entries separated by a line containing just '%'.
    # The .dat index built on Linux is unreadable by macOS fortune,
    # so we parse the raw text file directly.
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

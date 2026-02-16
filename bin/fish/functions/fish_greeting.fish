function fish_greeting
  # Find chinese fortunes in nix store by following the fortune symlink
  set fortune_store (readlink (which fortune) | string replace '/bin/fortune' '')
  if test -f "$fortune_store/share/games/fortunes/chinese"
    fortune -s "$fortune_store/share/games/fortunes/chinese"
  else
    echo "Chinese fortunes not found"
  end
end

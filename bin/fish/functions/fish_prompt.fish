function fish_prompt --description 'Write out the prompt'
  set -l last_pipestatus $pipestatus
  set -lx __fish_last_status $status

  set -l suffix '>'
  if functions -q fish_is_root_user; and fish_is_root_user
      set suffix '#'
  end

  # host-specific icon
  set -l host_icon '鱼'
  set -l hn (cat /etc/hostname 2>/dev/null; or hostname 2>/dev/null; or echo 'unknown')
  set hn (string trim $hn)
  switch $hn
      case 'ene' 'ene-1'
          set host_icon '🩵'
      case 'rook'
          set host_icon '♜'
      case 'chateau' 'chat'
          set host_icon '🍹'
      case 'kiss'
          set host_icon '💋'
  end

  echo -n -s (set_color brblack) "$hn " (set_color blue) "$host_icon " (set_color brblue) (prompt_pwd) $suffix " "
end

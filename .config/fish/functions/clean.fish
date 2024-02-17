function clean
  set -l options (fish_opt -s q -l query)
  set options $options (fish_opt -s c -l cache)

  argparse $options -- $argv
  or return 1

  if set -q _flag_query
    # evaluate cleanliness
    set -l home_cln (ls -a | wc -l)

    set -l clean_color
    if test "$home_cln" -gt 50
      set clean_color (set_color red)
    else if test "$home_cln" -gt 30
      set clean_color (set_color yellow)
    else
      set clean_color (set_color green)
    end 
    echo "homedir cleanliness:" $clean_color$home_cln
    return 0
  end

  if set -q _flag_cache
    # clean common caches
    exec rm -rf .local/state/nvim/swap/*
    return 0
  end
end


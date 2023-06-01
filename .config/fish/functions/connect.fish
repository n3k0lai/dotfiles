# bc i always forget how to use nmcli
function connect
  set -l options (fish_opt -s l -l list)
  set options $options (fish_opt -s i -l id --required-val)
  
  argparse $options -- $argv
  or return 1
  
  if set -q _flag_list
      nmcli -f all dev wifi list
      return 0
  end
  
  if set -q _flag_id
      sudo nmcli dev wifi connect "$_flag_id" -a
      return 0
  end
end

function lemonbar_time
  set bar_time (date +%I:%M)
  echo -n $bar_time

end

function lemonbar
  while true
    echo "${r}"(lemonbar_time)
    sleep 1
  end
end

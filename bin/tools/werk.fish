# a windows RDP wrapper
function werk
  source ~/.ssh/workcreds.fish
  or echo "creds not found, choom." # use set -x, no function wrapper
  and echo "logging into $WORK_IP"
  xfreerdp /w:1920 /h:1050 /u:$WORK_USR /p:$WORK_PWD /v:$WORK_IP
end

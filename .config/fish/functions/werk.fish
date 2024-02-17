# a windows RDP wrapper
function werk --argument-names cmd
    source ~/.ssh/workcreds.fish or echo "creds not found, choom." # use set -x, no function wrapper
    and echo "logging into $WORK_IP"
    switch "$cmd"
        # case for local ip
        case -l
            xfreerdp /w:2560 /h:1340 /u:$WORK_USR /p:$WORK_PWD /v:$WORK_IP
        case ""
            xfreerdp /w:1920 /h:1050 /u:$WORK_USR /p:$WORK_PWD /v:$WORK_IP
    end
end

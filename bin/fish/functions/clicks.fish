# Clicks Power Keyboard — scan / pair / reconnect
#
# Pairing is per host adapter. After `clicks pair`, save the MAC in
# modules/hardware/clicks.nix so other machines get the same helper.

function clicks --description 'Clicks Power Keyboard bluetooth helper'
    set -l cmd ''
    if test (count $argv) -gt 0
        set cmd $argv[1]
        set -e argv[1]
    end

    switch "$cmd"
        case '' status st
            _clicks_status
        case scan s
            _clicks_scan $argv
        case pair p
            _clicks_pair $argv
        case connect c
            _clicks_connect $argv
        case disconnect d
            _clicks_disconnect $argv
        case forget rm
            _clicks_forget $argv
        case help h -h --help
            _clicks_help
        case '*'
            echo "unknown command: $cmd (try: clicks help)" >&2
            return 1
    end
end

function _clicks_help
    set -l host (hostname)
    set -l ch (_clicks_channel_for $host)
    echo "clicks — Clicks Power Keyboard (BLE)"
    echo ""
    echo "  clicks status|st          adapter + paired Clicks devices"
    echo "  clicks scan|s [seconds]   LE scan for Power Keyboard"
    echo "  clicks pair|p [9|MAC]     pair slot 9 (or a MAC). Keyboard must be pairing."
    echo "  clicks connect|c [MAC]    connect a known / given device"
    echo "  clicks disconnect|d [MAC] disconnect"
    echo "  clicks forget|rm [MAC]    remove pairing from this host"
    echo ""
    echo "Pair this host ($host), suggested channel $ch:"
    echo "  1. Hold Power + $ch until the LED flashes blue"
    echo "     (first-ever pair: power on and slide the keyboard open)"
    echo "  2. clicks pair"
    echo "  3. If a passkey is shown, type it on the Clicks keyboard and press Enter"
    echo "  4. Save the MAC in modules/hardware/clicks.nix (devices = [...])"
    echo ""
    echo "Switch hosts later: hold Power + that host's channel (solid blue = connected)"
    echo "Clear a channel:    connect to it, then SYM+0"
    echo ""
    echo "BlueZ bonds are per adapter — kiss and rook each need their own pair."
    if test -s /etc/clicks/channels
        echo ""
        echo "Channel map (/etc/clicks/channels):"
        cat /etc/clicks/channels
    end
end

function _clicks_channel_for --argument-names host
    if test -s /etc/clicks/channels
        set -l line (string match -r "^$host=.+" </etc/clicks/channels)
        if test -n "$line"
            echo (string split -m 1 = -- $line)[2]
            return
        end
    end
    echo '?'
end

function _clicks_need_bt
    if not command -q bluetoothctl
        echo "bluetoothctl not found — enable hardware.clicks and nixos-rebuild" >&2
        return 1
    end
    if not systemctl is-active --quiet bluetooth
        echo "starting bluetooth.service..."
        sudo systemctl start bluetooth
        or return 1
    end
    # A leftover bluetoothctl scan owns discovery and DELs new ads.
    # pkill (procps) — NixOS has no killall unless psmisc is installed.
    _clicks_stop_scan
    or true
    pkill -x bluetoothctl >/dev/null 2>&1
    or true
    bluetoothctl power on >/dev/null
    or return 1
    bluetoothctl pairable on >/dev/null
    or true
    # scan off errors when discovery is already idle
    bluetoothctl scan off >/dev/null 2>&1
    or true
    return 0
end

function _clicks_names
    echo Clicks Power Keyboard
    echo Power Keyboard
    echo Power Keys
    if test -s /etc/clicks/name-match
        while read -l line
            set -l line (string trim -- $line)
            test -z "$line"; and continue
            string match -q '#*' -- $line; and continue
            echo $line
        end </etc/clicks/name-match
    end
end

function _clicks_is_clicks --argument-names name
    set -l n (string lower -- (string trim -- $name))
    test -z "$n"; and return 1
    # Unnamed scan hits are hex / MAC aliases — never pair those.
    if string match -qr '^[0-9a-f:._-]+$' -- $n
        return 1
    end
    for pat in (_clicks_names)
        set -l p (string lower -- (string trim -- $pat))
        # `string match -r '\S'` used to shrink patterns to "c"/"p" and
        # match every device whose name contained those letters.
        if test (string length -- $p) -lt 4
            continue
        end
        if string match -q "*$p*" -- $n
            return 0
        end
    end
    return 1
end

function _clicks_known
    # prints: address<TAB>name<TAB>channel<TAB>host
    if not test -s /etc/clicks/devices
        return 0
    end
    while read -l line
        set -l line (string trim -- $line)
        test -z "$line"; and continue
        string match -q '#*' -- $line; and continue
        set -l parts (string split '|' -- $line)
        set -l addr $parts[1]
        test -z "$addr"; and continue
        echo -s $addr \t $parts[2] \t $parts[3] \t $parts[4]
    end </etc/clicks/devices
end

function _clicks_mac_for_host
    set -l host (hostname)
    for row in (_clicks_known)
        set -l parts (string split \t -- $row)
        if test "$parts[4]" = "$host"
            echo $parts[1]
            return 0
        end
    end
    # fall back to first known address
    for row in (_clicks_known)
        set -l parts (string split \t -- $row)
        if test -n "$parts[1]"
            echo $parts[1]
            return 0
        end
    end
    return 1
end

function _clicks_resolve_mac
    if test (count $argv) -gt 0
        echo $argv[1]
        return 0
    end
    set -l mac (_clicks_mac_for_host)
    if test -n "$mac"
        echo $mac
        return 0
    end
    echo "no MAC given and none in /etc/clicks/devices — run: clicks scan" >&2
    return 1
end

function _clicks_status
    _clicks_need_bt
    or return 1
    echo "=== adapter ==="
    bluetoothctl show | string match -r '^(Controller |	Name:|	Powered:|	Discovering:|	Alias:).*'
    echo ""
    echo "=== paired / known ==="
    set -l found 0
    for line in (bluetoothctl devices)
        set -l mac (echo $line | awk '{print $2}')
        set -l name (echo $line | awk '{$1=$2=""; print substr($0,3)}')
        if _clicks_is_clicks "$name"
            or test -n "$mac"; and string match -q '*'"$mac"'*' -- (string collect (_clicks_known))
            set found 1
            echo $line
            bluetoothctl info $mac | string match -r '^\s+(Name:|Paired:|Trusted:|Connected:|Address:|Identity:).*'
            echo ""
        end
    end
    if test $found -eq 0
        echo "(none — try: clicks scan)"
    end
    set -l known (_clicks_known)
    if test (count $known) -gt 0
        echo "=== /etc/clicks/devices ==="
        for row in $known
            echo $row | string replace \t '  '
        end
    end
end

function _clicks_deansi --argument-names text
    string replace -ra '\e\[[0-9;]*[mK]' '' -- $text
end

function _clicks_mac_from_line --argument-names line
    set -l m (string match -r 'Device ([0-9A-Fa-f:]{17})' -- $line)
    if test (count $m) -ge 2
        echo $m[2]
    end
end

# Prints mac|name from a bluetoothctl scan log (NEW / Name / Alias lines).
function _clicks_parse_scanlog --argument-names file
    test -r $file
    or return
    while read -l line
        set -l line (_clicks_deansi $line)
        set -l m (string match -r 'Device ([0-9A-Fa-f:]{17}) Name: (.+)' -- $line)
        if test (count $m) -ge 3
            echo "$m[2]|$m[3]"
            continue
        end
        set -l m (string match -r 'Device ([0-9A-Fa-f:]{17}) Alias: (.+)' -- $line)
        if test (count $m) -ge 3
            echo "$m[2]|$m[3]"
            continue
        end
        set -l m (string match -r 'NEW\] Device ([0-9A-Fa-f:]{17}) (.+)$' -- $line)
        if test (count $m) -ge 3
            echo "$m[2]|$m[3]"
        end
    end <$file
end

function _clicks_hid_macs --argument-names file
    test -r $file
    or return
    set -l seen
    while read -l line
        set -l line (_clicks_deansi $line)
        set -l mac (_clicks_mac_from_line $line)
        test -n "$mac"; or continue
        if string match -q '*Icon: input-keyboard*' -- $line
            or string match -q '*00001812-*' -- $line
            or string match -qr 'Class: 0x000025[34]0' -- $line
            if not contains -- $mac $seen
                set -a seen $mac
                echo $mac
            end
        end
    end <$file
end

function _clicks_named_from_log --argument-names file
    set -l seen
    for row in (_clicks_parse_scanlog $file)
        set -l parts (string split -m 1 '|' -- $row)
        set -l mac $parts[1]
        set -l name $parts[2]
        _clicks_is_clicks "$name"; or continue
        if not contains -- $mac $seen
            set -a seen $mac
            echo "$mac|$name"
        end
    end
end

function _clicks_pick_from_log --argument-names file
    set -l hit (_clicks_named_from_log $file)
    if test (count $hit) -gt 0
        echo $hit[1]
        return 0
    end
    set -l hid (_clicks_hid_macs $file)
    if test (count $hid) -gt 0
        echo "$hid[1]|HID-keyboard"
        return 0
    end
    return 1
end

function _clicks_dump_scanlog --argument-names file
    set -l macs
    set -l names
    for row in (_clicks_parse_scanlog $file)
        set -l parts (string split -m 1 '|' -- $row)
        set -l mac $parts[1]
        set -l name (string trim -- $parts[2])
        test -n "$mac"; or continue
        set -l idx (contains -i -- $mac $macs)
        if test $status -eq 0
            set names[$idx] $name
        else
            set -a macs $mac
            set -a names $name
        end
    end
    if test (count $macs) -eq 0
        echo "  (scan log had no Device lines — discovery may not have started)"
        return
    end
    set -l i 1
    while test $i -le (count $macs)
        set -l rssi (_clicks_last_rssi $file $macs[$i])
        echo "  $macs[$i]  $names[$i]  rssi=$rssi"
        set i (math $i + 1)
    end
end

function _clicks_last_rssi --argument-names file mac
    set -l last '?'
    if test -r $file
        for line in (string match -r "Device $mac RSSI:.*" < $file)
            set -l m (string match -r '\((-?[0-9]+)\)' -- (_clicks_deansi $line))
            if test (count $m) -ge 2
                set last $m[2]
            end
        end
    end
    echo $last
end

function _clicks_is_mesh --argument-names file mac
    test -r $file
    or return 1
    string match -q "*Device $mac UUIDs: 00001828-*" -- (_clicks_deansi (cat $file))
end

# Android resolves HOGP names by connecting. BlueZ often leaves the ad nameless.
function _clicks_probe --argument-names mac
    echo "probing $mac to read GAP name (5s timeout)..." >&2
    timeout 5 bluetoothctl connect $mac >/dev/null 2>&1
    set -l info (timeout 3 bluetoothctl info $mac)
    printf '%s\n' $info | string match -r '^\s+(Name:|Alias:|Icon:|Paired:|Connected:|UUID:).*' >&2
    set -l name
    for line in $info
        set -l m (string match -r 'Name: (.+)$' -- $line)
        if test (count $m) -ge 2
            set name $m[2]
        end
    end
    timeout 2 bluetoothctl disconnect $mac >/dev/null 2>&1
    or true
    if test -n "$name"; and _clicks_is_clicks "$name"
        echo "$mac|$name"
        return 0
    end
    echo "  (not a Clicks keyboard: name='$name')" >&2
    return 1
end

# Timed LE scan. A fifo-driven bluetoothctl deadlocks (writer closes between
# echo lines, next echo blocks forever). --timeout keeps discovery owned.
function _clicks_begin_scan --argument-names file seconds
    bluetoothctl pairable on >/dev/null 2>&1
    or true
    if command -q stdbuf
        stdbuf -oL bluetoothctl --timeout $seconds scan le >$file 2>&1 &
    else
        bluetoothctl --timeout $seconds scan le >$file 2>&1 &
    end
    set -g _clicks_scan_pid $last_pid
end

function _clicks_stop_scan
    if test -n "$_clicks_scan_pid"
        kill $_clicks_scan_pid 2>/dev/null
        wait $_clicks_scan_pid 2>/dev/null
        set -g _clicks_scan_pid ''
    end
    return 0
end

function _clicks_scan --argument-names seconds
    _clicks_need_bt
    or return 1
    if test -z "$seconds"
        set seconds 20
    end
    echo "scanning LE for $seconds s — hold Power + channel until LED flashes blue"
    set -l log /tmp/clicks-last-scan.log
    _clicks_begin_scan $log $seconds
    wait $_clicks_scan_pid
    set -g _clicks_scan_pid ''
    echo ""
    echo "=== devices ==="
    _clicks_dump_scanlog $log
    echo "=== HID keyboards ==="
    set -l hid (_clicks_hid_macs $log)
    if test (count $hid) -eq 0
        echo "  (none)"
    else
        printf '  %s\n' $hid
    end
    echo "=== name matches ==="
    set -l found 0
    for row in (_clicks_named_from_log $log)
        echo "  "(string replace '|' '  ' -- $row)
        set found 1
    end
    if test $found -eq 0
        echo "(no Power Keyboard name seen — log kept at $log)"
        return 1
    end
end

function _clicks_pair
    _clicks_need_bt
    or return 1
    set -l host (hostname)
    set -l ch (_clicks_channel_for $host)
    set -l mac ''
    set -l label ''
    if test (count $argv) -gt 0
        if string match -qr '^[1-9]$' -- $argv[1]
            set ch $argv[1]
        else
            set mac $argv[1]
        end
    end

    bluetoothctl agent KeyboardDisplay >/dev/null
    bluetoothctl default-agent >/dev/null
    bluetoothctl discoverable on >/dev/null 2>&1
    or true

    set -l log /tmp/clicks-last-scan.log
    set -l probed
    if test -z "$mac"
        echo "Put the keyboard in pairing mode NOW (slot $ch):"
        echo "  1. Phones' Bluetooth off"
        echo "  2. Slide the keyboard open, hold it near the PC"
        echo "  3. Hold Power + $ch until the LED flashes BLUE (not white/solid)"
        echo "scanning LE 45s (will probe unnamed ads), log: $log"
        _clicks_begin_scan $log 45
        for n in (seq 1 43)
            if not kill -0 $_clicks_scan_pid 2>/dev/null
                break
            end
            set -l hit (_clicks_pick_from_log $log)
            if test -n "$hit"
                set mac (string split -m 1 '|' -- $hit)[1]
                set label (string split -m 1 '|' -- $hit)[2]
                break
            end
            # After 8s, connect to unnamed ads so GAP names resolve (Android does this).
            if test $n -eq 8 -o $n -eq 18 -o $n -eq 28
                for row in (_clicks_parse_scanlog $log)
                    set -l parts (string split -m 1 '|' -- $row)
                    set -l cand $parts[1]
                    contains -- $cand $probed; and continue
                    _clicks_is_mesh $log $cand; and continue
                    set -l rssi (_clicks_last_rssi $log $cand)
                    # Desk keyboard is typically -30..-60. AX200+USB3 can be worse,
                    # but -80 and below is another room — connect hangs for 30s+.
                    if not string match -qr '^-?[0-9]+$' -- $rssi
                        continue
                    end
                    if test $rssi -lt -75
                        echo "  skip $cand rssi=$rssi (too weak to be the keyboard)"
                        set -a probed $cand
                        continue
                    end
                    echo "  unnamed $cand rssi=$rssi — probing"
                    set -a probed $cand
                    set -l phit (_clicks_probe $cand)
                    if test $status -eq 0
                        set mac (string split -m 1 '|' -- $phit)[1]
                        set label (string split -m 1 '|' -- $phit)[2]
                        break
                    end
                end
                test -n "$mac"; and break
            end
            if test (math $n % 5) -eq 0
                echo "  still scanning ($n s)..."
            end
            sleep 1
        end
    end

    if test -z "$mac"
        echo "keyboard not found. Devices the adapter actually saw:" >&2
        _clicks_dump_scanlog $log
        echo "HID-class ads:" >&2
        set -l hid (_clicks_hid_macs $log)
        if test (count $hid) -eq 0
            echo "  (none)" >&2
        else
            printf '  %s\n' $hid >&2
        end
        _clicks_stop_scan
        echo "If a MAC above is the keyboard: clicks pair THAT_MAC" >&2
        echo "Full log: $log" >&2
        return 1
    end

    echo "pairing $mac  $label"
    echo "(if a passkey appears, type it on the Clicks keyboard, then Enter)"
    bluetoothctl pair $mac
    set -l st $status
    _clicks_stop_scan
    test $st -eq 0
    or return 1
    bluetoothctl trust $mac
    bluetoothctl connect $mac
    echo ""
    echo "paired. identity:"
    bluetoothctl info $mac | string match -r '^\s+(Name:|Paired:|Trusted:|Connected:|Address:|Identity:).*'
    echo ""
    echo "Add this to hardware.clicks.devices on $host (channel $ch):"
    echo "  { address = \"$mac\"; channel = $ch; host = \"$host\"; }"
end

function _clicks_connect
    _clicks_need_bt
    or return 1
    set -l mac (_clicks_resolve_mac $argv)
    or return 1
    echo "connecting $mac"
    bluetoothctl connect $mac
end

function _clicks_disconnect
    _clicks_need_bt
    or return 1
    set -l mac (_clicks_resolve_mac $argv)
    or return 1
    echo "disconnecting $mac"
    bluetoothctl disconnect $mac
end

function _clicks_forget
    _clicks_need_bt
    or return 1
    set -l mac (_clicks_resolve_mac $argv)
    or return 1
    echo "removing $mac from this host"
    bluetoothctl disconnect $mac >/dev/null 2>&1
    bluetoothctl remove $mac
end

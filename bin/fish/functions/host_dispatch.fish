# Shared ene/rook host ops: rebuild, pull, hermes hop, grok, status.
# Public entrypoints: ene.fish / rook.fish
#
#   host_dispatch --target ene --ssh nicho@ene --flake-env ENE_FLAKE_DIR $argv
#   host_dispatch --target rook --ssh nicho@rook --flake-env ROOK_FLAKE_DIR $argv
#
# Remote note: nicho's login shell is fish. `ssh host 'cmd'` becomes `fish -c cmd`,
# so bash scripts cannot be passed as the ssh command string. Non-interactive
# remote work is always:  printf script | ssh host bash --noprofile --norc -s

function host_dispatch
    argparse 'target=' 'ssh=' 'flake-env=' -- $argv
    or return 2

    set -l target $_flag_target
    set -l ssh_dest $_flag_ssh
    set -l flake_env $_flag_flake_env

    if test -z "$target"
        echo "host_dispatch: --target is required" >&2
        return 2
    end

    # Optional override: ENE_SSH / ROOK_SSH
    set -l ssh_override_var (string upper -- $target)_SSH
    if set -q $ssh_override_var
        set ssh_dest $$ssh_override_var
    else if test -z "$ssh_dest"
        set ssh_dest "nicho@$target"
    end

    set -l this_host (string lower -- (uname -n))
    set -l current_user (id -un)
    set -l hermes_home /var/lib/hermes
    set -l hermes_soul $hermes_home/.hermes
    set -l hermes_flake $hermes_home/dotfiles
    set -l home_flake $HOME/dotfiles

    set -l on_host_flake $home_flake
    if test -e $hermes_flake
        set on_host_flake $hermes_flake
    end

    set -l flake_dir $home_flake
    if test -n "$flake_env"; and set -q $flake_env
        set flake_dir $$flake_env
    end

    set -l on_target false
    set -l on_kiss false
    test "$this_host" = "$target"; and set on_target true
    test "$this_host" = kiss; and set on_kiss true

    set -l cmd ''
    if test (count $argv) -gt 0
        set cmd $argv[1]
        set -e argv[1]
    end

    # Resolve flake path for rebuild / update
    set -l active_flake $flake_dir
    if test "$on_target" = true
        set active_flake $on_host_flake
    end

    set -l rebuild_base ''
    if test "$on_target" = true
        set rebuild_base "sudo nixos-rebuild --flake $active_flake#$target"
    else if test "$on_kiss" = true
        set rebuild_base "nixos-rebuild --flake $active_flake#$target --target-host $ssh_dest --use-remote-sudo"
    else if test -n "$flake_env"; and set -q $flake_env
        set rebuild_base "sudo nixos-rebuild --flake $active_flake#$target"
    end

    # Escape argv for embedding in a remote bash script body
    set -l escaped_args
    for a in $argv
        set -a escaped_args (string escape -- $a)
    end
    set -l joined_args (string join ' ' -- $escaped_args)

    switch "$cmd"
        case test t
            if test -z "$rebuild_base"
                echo "$target: unknown host '$this_host' (expected kiss or $target; or set $flake_env)" >&2
                return 1
            end
            echo "🔨 nixos-rebuild test #$target..."
            eval $rebuild_base test

        case switch s
            if test -z "$rebuild_base"
                echo "$target: unknown host '$this_host' (expected kiss or $target; or set $flake_env)" >&2
                return 1
            end
            echo "🚀 nixos-rebuild switch #$target..."
            eval $rebuild_base switch

        case build b
            if test -z "$rebuild_base"
                echo "$target: unknown host '$this_host' (expected kiss or $target; or set $flake_env)" >&2
                return 1
            end
            echo "📦 nixos-rebuild build #$target..."
            eval $rebuild_base build

        case diff d
            if test -z "$rebuild_base"
                echo "$target: unknown host '$this_host' (expected kiss or $target; or set $flake_env)" >&2
                return 1
            end
            echo "📋 closure diff for #$target..."
            eval $rebuild_base build
            and if test "$on_target" = true
                nix store diff-closures /run/current-system ./result
            else
                echo "(built remotely; run diff on-host for local result symlink)"
            end

        case update u
            echo "🔄 nix flake update — $active_flake"
            nix flake update --flake $active_flake

        case pull p
            if test "$on_target" = true
                echo "📥 git pull --ff-only in $on_host_flake ..."
                git -C $on_host_flake pull --ff-only
            else if test "$on_kiss" = true
                echo "📥 git pull --ff-only on $ssh_dest (nicho dotfiles) ..."
                set -l pull_script "set -e
if test -e $hermes_flake; then
  git -C $hermes_flake pull --ff-only
else
  git -C \"\$HOME/dotfiles\" pull --ff-only
fi"
                printf '%s\n' "$pull_script" | ssh $ssh_dest bash --noprofile --norc -s
            else
                echo "$target: pull needs to run on $target or from kiss" >&2
                return 1
            end

        case shell sh
            if test "$on_target" = true
                exec sudo -u hermes -i
            else if test "$on_kiss" = true
                # Interactive hermes login (hermes shell is bash; sudo -i is fine)
                ssh -t $ssh_dest -- sudo -u hermes -i
            else
                echo "$target: shell needs to run on $target or from kiss" >&2
                return 1
            end

        case grok g
            set -l grok_script "set -e
cd \"$hermes_soul\"
if command -v grok-update >/dev/null 2>&1; then
  echo 'Updating Grok CLI (hermes)...'
  grok-update || true
fi
BIN=\"\$HOME/.grok/bin/grok\"
if [ ! -x \"\$BIN\" ]; then
  echo \"grok: not found at \$BIN\" >&2
  exit 127
fi
exec \"\$BIN\" $joined_args"
            set -l hermes_bash sudo -u hermes env HOME=$hermes_home USER=hermes HERMES_HOME=$hermes_soul bash --noprofile --norc -s
            if test "$on_target" = true
                printf '%s\n' "$grok_script" | $hermes_bash
            else if test "$on_kiss" = true
                # stdin → remote bash -s as hermes (avoid fish parsing bash scripts)
                printf '%s\n' "$grok_script" | ssh -t $ssh_dest $hermes_bash
            else
                echo "$target: grok needs to run on $target or from kiss" >&2
                return 1
            end

        case do
            if test (count $argv) -eq 0
                echo "usage: $target do <command…>" >&2
                echo "  e.g. $target do hermes doctor" >&2
                return 2
            end
            set -l do_script "set -e
cd \"$hermes_soul\"
exec $joined_args"
            set -l hermes_bash sudo -u hermes env HOME=$hermes_home USER=hermes HERMES_HOME=$hermes_soul bash --noprofile --norc -s
            if test "$on_target" = true
                printf '%s\n' "$do_script" | $hermes_bash
            else if test "$on_kiss" = true
                printf '%s\n' "$do_script" | ssh -t $ssh_dest $hermes_bash
            else
                echo "$target: do needs to run on $target or from kiss" >&2
                return 1
            end

        case status st
            set -l status_script "echo '=== hermes-agent ==='
systemctl status hermes-agent --no-pager -l || true
echo ''
echo '=== hermes-dashboard ==='
systemctl status hermes-dashboard --no-pager -l 2>/dev/null || true
echo ''
echo '=== hermes status (CLI, as hermes) ==='
sudo -u hermes env HOME=$hermes_home HERMES_HOME=$hermes_soul hermes status 2>/dev/null || echo '(hermes CLI status unavailable)'"
            if test "$on_target" = true
                printf '%s\n' "$status_script" | bash --noprofile --norc -s
            else if test "$on_kiss" = true
                printf '%s\n' "$status_script" | ssh $ssh_dest bash --noprofile --norc -s
            else
                echo "$target: status needs to run on $target or from kiss" >&2
                return 1
            end

        case logs l
            if test "$on_target" = true
                journalctl -u hermes-agent -f --no-pager
            else if test "$on_kiss" = true
                ssh -t $ssh_dest -- journalctl -u hermes-agent -f --no-pager
            else
                echo "$target: logs need to run on $target or from kiss" >&2
                return 1
            end

        case restart rs
            # Restart hermes gateway (picks up env/config without full nixos switch)
            set -l restart_script "set -e
echo '🔄 sudo systemctl restart hermes-agent on $target...'
sudo systemctl restart hermes-agent
sleep 2
systemctl is-active hermes-agent
systemctl status hermes-agent --no-pager -l | head -20
"
            if test "$on_target" = true
                printf '%s\n' "$restart_script" | bash --noprofile --norc -s
            else if test "$on_kiss" = true
                printf '%s\n' "$restart_script" | ssh $ssh_dest bash --noprofile --norc -s
            else
                echo "$target: restart needs to run on $target or from kiss" >&2
                return 1
            end

        case a2a
            # A2A ops: status | smoke | card | restart | tools
            set -l a2a_sub status
            if test (count $argv) -gt 0
                set a2a_sub $argv[1]
                set -e argv[1]
            end

            # MagicDNS: ene / rook (match NixOS hostnames; no ene-1 / chat legacy)
            set -l a2a_self_url
            set -l a2a_peer_url
            set -l a2a_peer_name
            if test "$target" = ene
                set a2a_self_url "http://ene.bushbaby-mercat.ts.net:9900"
                set a2a_peer_url "http://rook.bushbaby-mercat.ts.net:9900"
                set a2a_peer_name rook
            else if test "$target" = rook
                set a2a_self_url "http://rook.bushbaby-mercat.ts.net:9900"
                set a2a_peer_url "http://ene.bushbaby-mercat.ts.net:9900"
                set a2a_peer_name ene
            else
                set a2a_self_url "http://127.0.0.1:9900"
                set a2a_peer_url ""
                set a2a_peer_name ""
            end

            set -l a2a_script
            switch "$a2a_sub"
                case status st s ''
                    set a2a_script "set +e
echo '=== A2A status ($target) ==='
echo \"self card: $a2a_self_url/.well-known/agent-card.json\"
curl -sS -m 8 \"$a2a_self_url/.well-known/agent-card.json\" 2>&1 | head -c 1200
echo ''
echo ''
echo '--- env keys (names only) ---'
sudo -u hermes bash -c 'grep -E \"^A2A_\" $hermes_soul/.env 2>/dev/null | sed \"s/=.*/=***/\"' || true
echo ''
echo '--- config.yaml a2a ---'
sudo -u hermes bash -c 'grep -n -E \"a2a|A2A\" $hermes_soul/config.yaml 2>/dev/null | head -40' || true
echo ''
echo '--- listen ---'
ss -tlnp 2>/dev/null | grep -E ':9900\\b' || echo '(nothing on :9900)'
echo ''
echo '--- recent journal ---'
journalctl -u hermes-agent -n 30 --no-pager 2>/dev/null | grep -i a2a | tail -15 || true
"
                case smoke sm
                    set a2a_script "set +e
echo '=== A2A smoke ($target) ==='
ok=0
echo -n \"self  $a2a_self_url ... \"
if curl -sS -m 8 -o /tmp/a2a-self.json -w '%{http_code}' \"$a2a_self_url/.well-known/agent-card.json\" | tee /tmp/a2a-self.code | grep -q 200; then
  echo OK
  head -c 400 /tmp/a2a-self.json; echo
  ok=\$((ok+1))
else
  echo FAIL code=\$(cat /tmp/a2a-self.code 2>/dev/null)
fi
if [ -n \"$a2a_peer_url\" ]; then
  echo -n \"peer  $a2a_peer_url ($a2a_peer_name) ... \"
  if curl -sS -m 8 -o /tmp/a2a-peer.json -w '%{http_code}' \"$a2a_peer_url/.well-known/agent-card.json\" | tee /tmp/a2a-peer.code | grep -q 200; then
    echo OK
    head -c 400 /tmp/a2a-peer.json; echo
    ok=\$((ok+1))
  else
    echo FAIL code=\$(cat /tmp/a2a-peer.code 2>/dev/null)
  fi
fi
echo ''
echo \"smoke: \$ok endpoint(s) OK\"
[ \"\$ok\" -ge 1 ]
"
                case card c
                    set a2a_script "set -e
curl -sS -m 8 \"$a2a_self_url/.well-known/agent-card.json\"
echo
"
                case restart r
                    set a2a_script "set -e
echo '🔄 restarting hermes-agent (picks up A2A env + config)...'
sudo systemctl restart hermes-agent
sleep 2
systemctl is-active hermes-agent
ss -tlnp 2>/dev/null | grep -E ':9900\\b' || echo '(not listening on :9900 yet — check journal)'
"
                case tools t
                    # Non-interactive: activation already enables a2a toolset on switch.
                    # Interactive picker still available via: $target do hermes tools
                    set a2a_script "set -e
echo 'A2A toolset is enabled on activate (platform_toolsets += a2a).'
echo 'Checking soul config...'
if sudo -u hermes grep -n \"a2a\" $hermes_soul/config.yaml 2>/dev/null | head -20; then
  :
else
  echo '(no a2a lines yet — run $target switch first)'
fi
echo ''
echo \"Restart gateway:  $target restart\"
echo \"Interactive tools: $target do hermes tools\"
"
                case help h
                    echo "$target a2a — Agent-to-Agent ops"
                    echo ""
                    echo "  $target a2a status|st   agent card + env keys + listen + journal"
                    echo "  $target a2a smoke|sm    curl self (+ peer) agent-card.json"
                    echo "  $target a2a card|c      print self agent card"
                    echo "  $target a2a tools|t     ensure a2a toolset in soul config"
                    echo "  $target a2a restart|r   systemctl restart hermes-agent"
                    echo ""
                    echo "  self: $a2a_self_url"
                    if test -n "$a2a_peer_url"
                        echo "  peer: $a2a_peer_url ($a2a_peer_name)"
                    end
                    echo ""
                    echo "  Deploy path: edit secrets + module → $target switch → $target a2a smoke"
                    echo "  As hermes:   $target do hermes tools   (interactive tool picker)"
                    return 0
                case '*'
                    echo "unknown a2a subcommand: $a2a_sub (try: $target a2a help)" >&2
                    return 1
            end

            if test "$on_target" = true
                printf '%s\n' "$a2a_script" | bash --noprofile --norc -s
            else if test "$on_kiss" = true
                printf '%s\n' "$a2a_script" | ssh $ssh_dest bash --noprofile --norc -s
            else
                echo "$target: a2a needs to run on $target or from kiss" >&2
                return 1
            end

        case '' help h
            echo "$target — host ops (rebuild + hermes hop)"
            echo ""
            echo "  Rebuild (nicho)"
            echo "    $target test|t       build + activate (no boot entry)"
            echo "    $target switch|s     build + activate + boot entry"
            echo "    $target build|b      build only"
            echo "    $target diff|d       build + closure diff"
            echo "    $target update|u     flake update"
            echo "    $target pull|p       git pull --ff-only nicho dotfiles on host"
            echo ""
            echo "  Hermes"
            echo "    $target shell|sh     interactive login as hermes"
            echo "    $target grok|g …     update + run hermes Grok in .hermes"
            echo "    $target do <cmd…>    run command as hermes (e.g. hermes doctor / hermes tools)"
            echo "    $target status|st    systemd units + hermes status"
            echo "    $target logs|l       follow hermes-agent journal"
            echo "    $target restart|rs   sudo systemctl restart hermes-agent"
            echo "    $target a2a …        A2A status/smoke/card/tools/restart (see $target a2a help)"
            echo ""
            echo "  host:   $this_host"
            echo "  user:   $current_user"
            echo "  target: #$target → flake: $active_flake"
            echo "  ssh:    $ssh_dest"
            if test "$on_kiss" = true
                echo "  mode:   remote (kiss → $target)"
            else if test "$on_target" = true
                echo "  mode:   local on $target"
            else
                echo "  mode:   unknown host (set $flake_env or run from kiss/$target)"
            end
            if test -n "$rebuild_base"
                echo "  rebuild: $rebuild_base <test|switch|build>"
            end

        case '*'
            echo "unknown command: $cmd (try: $target help)" >&2
            return 1
    end
end

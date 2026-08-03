# Shared ene/rook host ops: rebuild, pull, hermes hop, grok, status.
# Public entrypoints: ene.fish / rook.fish
#
#   host_dispatch --target ene --ssh nicho@ene --flake-env ENE_FLAKE_DIR $argv
#   host_dispatch --target rook --ssh nicho@rook --flake-env ROOK_FLAKE_DIR $argv

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

    # Escape argv for embedding in a remote bash -lc string
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
                ssh $ssh_dest "if test -e $hermes_flake; then git -C $hermes_flake pull --ff-only; else git -C \$HOME/dotfiles pull --ff-only; fi"
            else
                echo "$target: pull needs to run on $target or from kiss" >&2
                return 1
            end

        case shell sh
            if test "$on_target" = true
                exec sudo -u hermes -i
            else if test "$on_kiss" = true
                ssh -t $ssh_dest "sudo -u hermes -i"
            else
                echo "$target: shell needs to run on $target or from kiss" >&2
                return 1
            end

        case grok g
            set -l grok_script '
                set -e
                export HOME='"$hermes_home"' USER=hermes HERMES_HOME='"$hermes_soul"'
                cd "$HERMES_HOME"
                if command -v grok-update >/dev/null 2>&1; then
                    echo "Updating Grok CLI (hermes)..."
                    grok-update || true
                fi
                BIN="$HOME/.grok/bin/grok"
                if [ ! -x "$BIN" ]; then
                    echo "grok: not found at $BIN" >&2
                    exit 127
                fi
                exec "$BIN" '"$joined_args"'
            '
            if test "$on_target" = true
                sudo -u hermes env HOME=$hermes_home USER=hermes HERMES_HOME=$hermes_soul \
                    bash -lc "$grok_script"
            else if test "$on_kiss" = true
                ssh -t $ssh_dest "sudo -u hermes env HOME=$hermes_home USER=hermes HERMES_HOME=$hermes_soul bash -lc "(string escape -- $grok_script)
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
            set -l do_script '
                set -e
                export HOME='"$hermes_home"' USER=hermes HERMES_HOME='"$hermes_soul"'
                cd "$HERMES_HOME"
                exec '"$joined_args"'
            '
            if test "$on_target" = true
                sudo -u hermes env HOME=$hermes_home USER=hermes HERMES_HOME=$hermes_soul \
                    bash -lc "$do_script"
            else if test "$on_kiss" = true
                ssh -t $ssh_dest "sudo -u hermes env HOME=$hermes_home USER=hermes HERMES_HOME=$hermes_soul bash -lc "(string escape -- $do_script)
            else
                echo "$target: do needs to run on $target or from kiss" >&2
                return 1
            end

        case status st
            # systemd unit health + hermes CLI status (as hermes user)
            set -l status_script '
                echo "=== hermes-agent ==="
                systemctl status hermes-agent --no-pager -l || true
                echo ""
                echo "=== hermes-dashboard ==="
                systemctl status hermes-dashboard --no-pager -l 2>/dev/null || true
                echo ""
                echo "=== hermes status (CLI, as hermes) ==="
                sudo -u hermes env HOME=/var/lib/hermes HERMES_HOME=/var/lib/hermes/.hermes \
                    hermes status 2>/dev/null || echo "(hermes CLI status unavailable)"
            '
            if test "$on_target" = true
                bash -c "$status_script"
            else if test "$on_kiss" = true
                ssh $ssh_dest "$status_script"
            else
                echo "$target: status needs to run on $target or from kiss" >&2
                return 1
            end

        case logs l
            if test "$on_target" = true
                journalctl -u hermes-agent -f --no-pager
            else if test "$on_kiss" = true
                ssh -t $ssh_dest "journalctl -u hermes-agent -f --no-pager"
            else
                echo "$target: logs need to run on $target or from kiss" >&2
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
            echo "    $target do <cmd…>    run command as hermes (e.g. hermes doctor)"
            echo "    $target status|st    systemd units + hermes status"
            echo "    $target logs|l       follow hermes-agent journal"
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

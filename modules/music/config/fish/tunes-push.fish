function tunes-push -d "Stage, commit, and push tunes repo"
    set -l repo ~/Code/tunes

    if not test -d $repo/.git
        echo "Tunes repo not found at $repo"
        echo "Run tunes-pull to clone it first."
        return 1
    end

    set -l msg $argv[1]
    if test -z "$msg"
        set msg (date "+%Y-%m-%d %H:%M")
    end

    git -C $repo add -A
    git -C $repo commit -m $msg
    git -C $repo push
end

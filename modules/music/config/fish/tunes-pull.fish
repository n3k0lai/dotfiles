function tunes-pull -d "Pull or clone the tunes repo"
    set -l repo ~/Code/tunes
    set -l url "git@github.com:n3k0lai/tunes.git"

    if not test -d $repo/.git
        echo "Cloning tunes repo..."
        git clone $url $repo
        return $status
    end

    git -C $repo pull --rebase
end

complete -c nx -f
complete -c nx -a "test" -d "Build + activate (no boot entry)"
complete -c nx -a "switch" -d "Build + activate + boot entry"
complete -c nx -a "build" -d "Build only"
complete -c nx -a "diff" -d "Build + show closure diff"
complete -c nx -a "update" -d "Update flake inputs"

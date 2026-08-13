# rook — host ops for the Rook server (rebuild + hermes hop + A2A + upload)
# On kiss: SSH Host "rook" (agenix ssh_config → rook.bushbaby-mercat.ts.net).
# On rook: local. Override with ROOK_SSH if needed.
# See: rook help · rook a2a help · rook upload help
function rook
    host_dispatch --target rook --ssh nicho@rook --flake-env ROOK_FLAKE_DIR $argv
end

# rook — host ops for the Rook server (rebuild + hermes hop)
# On kiss: SSH / --target-host to rook. On rook: local.
function rook
    host_dispatch --target rook --ssh nicho@rook --flake-env ROOK_FLAKE_DIR $argv
end

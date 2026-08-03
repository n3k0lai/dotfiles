# ene — host ops for the Ene server (rebuild + hermes hop)
# On kiss: SSH / --target-host to ene. On ene: local.
function ene
    host_dispatch --target ene --ssh nicho@ene --flake-env ENE_FLAKE_DIR $argv
end

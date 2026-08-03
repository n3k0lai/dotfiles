# ene — host ops for the Ene server (rebuild + hermes hop + A2A)
# On kiss: SSH Host "ene" (agenix ssh_config → ene.bushbaby-mercat.ts.net). On ene: local.
# See: ene help · ene a2a help
function ene
    host_dispatch --target ene --ssh nicho@ene --flake-env ENE_FLAKE_DIR $argv
end

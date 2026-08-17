# Forscan Windows guest lives on qemu:///system (libvirtd), not session.
# Do not grab the pointer/keyboard — Super stays on Hyprland.
function forscan --description 'Open the Forscan Windows VM console'
    set -l uri qemu:///system
    if not virsh -c $uri list --name | string match -q forscan
        virsh -c $uri start forscan
        or return 1
    end
    virt-viewer --connect $uri --attach \
        --hotkeys=release-cursor=shift+f12,toggle-fullscreen=shift+f11 \
        forscan $argv
end

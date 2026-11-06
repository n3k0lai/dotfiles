# Private host inventory

Evaluation-time LAN, Tailscale, MAC, and network-label values do not belong
in the public tree. They live in the private flake input `private`
(`github:n3k0lai/dotfiles-private`, `flake = false`).

`hosts.example.nix` (and `hosts.nix` here) are documentation placeholders
using TEST-NET addresses. Kiss, rook, and the other hosts merge the private
`hosts.nix` over those defaults via `specialArgs.privateHosts`.

Runtime labels for `eww` (`network.fish`) are written to
`/etc/dotfiles/network-labels` and may also be supplied at
`~/.config/eww/network-labels`.

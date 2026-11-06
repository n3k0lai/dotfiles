# Public placeholder inventory (RFC 5737 TEST-NET-3 and RFC 7042 docs MACs).
# Real values live in the private flake input `private` (n3k0lai/dotfiles-private).
# Override: nix eval --override-input private path:./modules/private
{
  lan = {
    pati0 = "203.0.113.10";
    c200 = "203.0.113.11";
  };
  macs = {
    pati0 = "00:00:5E:00:53:10";
    c200 = "00:00:5E:00:53:11";
  };
  tailscale = {
    rook = "203.0.113.100";
    domain = "example.ts.net";
    rookMagicDns = "rook.example.ts.net";
  };
  network = {
    kissEthernetLabel = "Home LAN";
    macLabels = { };
  };
}

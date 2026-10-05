# documentation.doc.enable installs every system package's "doc" output.
# python312.doc does not build on nixos-26.05: docutils 0.22 cannot parse
# the CPython Doc tree (python/cpython#139257), and Hydra has no cache.
# Man pages and info stay. Package HTML docs do not.
{ lib, ... }:
{
  documentation.doc.enable = lib.mkForce false;
}

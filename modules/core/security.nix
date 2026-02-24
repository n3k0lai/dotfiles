# modules/core/security.nix -- system hardening
# Inspired by hlissner/dotfiles/modules/security.nix
# Applied to all hosts for baseline protection.
{ lib, config, ... }:

{
  ## Filesystem security
  # tmpfs for /tmp — volatile, wiped on reboot, faster on SSD
  boot.tmp.useTmpfs = lib.mkDefault true;
  boot.tmp.cleanOnBoot = lib.mkDefault (!config.boot.tmp.useTmpfs);

  ## Bootloader security
  # Disable systemd-boot editor — prevents single-user mode access at boot
  boot.loader.systemd-boot.editor = lib.mkDefault false;

  ## Kernel hardening
  boot.kernel.sysctl = {
    # Disable Magic SysRq key (potential security concern)
    "kernel.sysrq" = 0;

    # Restrict kernel pointer exposure
    "kernel.kptr_restrict" = 2;

    # Restrict dmesg access to root
    "kernel.dmesg_restrict" = 1;

    ## TCP hardening
    # Prevent bogus ICMP errors from filling logs
    "net.ipv4.icmp_ignore_bogus_error_responses" = 1;

    # Reverse path filtering — mitigates IP spoofing
    "net.ipv4.conf.default.rp_filter" = 1;
    "net.ipv4.conf.all.rp_filter" = 1;

    # Do not accept IP source route packets (we're not a router)
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv6.conf.all.accept_source_route" = 0;

    # Don't send ICMP redirects (not a router)
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;

    # Refuse ICMP redirects (MITM mitigation)
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.secure_redirects" = 0;
    "net.ipv4.conf.default.secure_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;

    # SYN flood protection
    "net.ipv4.tcp_syncookies" = 1;

    # TIME-WAIT assassination protection
    "net.ipv4.tcp_rfc1337" = 1;

    ## TCP optimization
    # TCP Fast Open (both client and server)
    "net.ipv4.tcp_fastopen" = 3;
  };

  ## SSH hardening (baseline — hosts can override)
  services.openssh.settings = {
    # No root password login
    PermitRootLogin = lib.mkDefault "prohibit-password";
    # Key-only auth
    PasswordAuthentication = lib.mkDefault false;
    KbdInteractiveAuthentication = lib.mkDefault false;
  };
}

# Common container-runtime kernel setup, applied on import by the
# runtime aspects (docker.nix, podman.nix). Underscore files are
# skipped by the den import-tree. security.lockKernelModules = true,
# so every module needed at runtime must be listed here.
{ ... }:
{
  # Port mapping and bridge networking for dockerd, netavark, and the
  # CNI bridge/portmap/firewall plugins (Nomad bridge mode). xt_tcp
  # and xt_udp are aliases of xt_tcpudp. nft_masq/nft_nat/nft_redir:
  # netavark's native-nft NAT expressions; lockKernelModules blocks
  # their autoload, so without them bridge containers fail with
  # "nft did not return successfully" (kernel ENOENT on the expr).
  boot.kernelModules = [
    "ip_tables"
    "br_netfilter"
    "bridge"
    "veth"
    "overlay"
    "nf_conntrack"
    "nf_nat"
    "nf_tables"
    "nft_compat"
    "nft_chain_nat"
    "nft_ct"
    "nft_fib"
    "nft_fib_ipv4"
    "nft_fib_ipv6"
    "nft_fib_inet"
    "nft_masq"
    "nft_nat"
    "nft_redir"
    "iptable_filter"
    "iptable_nat"
    "iptable_mangle"
    "iptable_raw"
    "xt_tcpudp"
    "xt_MASQUERADE"
    "xt_multiport"
    "xt_REDIRECT"
    "xt_NETMAP"
    "xt_comment"
    "xt_mark"
  ];
}

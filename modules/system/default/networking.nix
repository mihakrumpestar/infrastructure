{ inputs, ... }:
let
  secretsDir = inputs.infrastructure-secrets;
in
{
  den.aspects.networking = {
    nixos =
      { config, lib, ... }:
      {
        options.my.networking.homeWifi = {
          enable = lib.mkEnableOption "Provision home wifi credentials on device";
          autoconnect.enable = lib.mkEnableOption "Whether to enable WiFi autoconnect";
        };

        config = {
          age.secrets.homeWifi = lib.mkIf config.my.networking.homeWifi.enable {
            file = "${secretsDir}/secrets/users/homeWifi.nmconnection.age";
            path = "/etc/NetworkManager/system-connections/homeWifi.nmconnection";
          };

          # Check: ss -tulnp
          services.resolved.settings.Resolve.DNSStubListener = false;

          networking = {
            useDHCP = false;
            firewall.enable = true;
            nftables.enable = true;
          };

          boot.kernel.sysctl = {
            # Enable IP forwarding for tailscale, kubernetes, and VMs
            "net.ipv4.ip_forward" = true; # Verify: "cat /proc/sys/net/ipv4/ip_forward" or "sysctl net.ipv4.ip_forward"
            "net.ipv6.conf.all.forwarding" = true;

            # For macvlan
            "net.ipv4.conf.all.arp_filter" = true;
            "net.ipv4.conf.all.rp_filter" = true;

            # Enable local routing
            "net.ipv4.conf.all.route_localnet" = true;

            # Optimistic memory allocation (eg. for Redis, Valkey)
            "vm.overcommit_memory" = 1;

            # Caddy quic: https://github.com/quic-go/quic-go/wiki/UDP-Buffer-Sizes
            "net.core.rmem_max" = 7500000;
            "net.core.wmem_max" = 7500000;
          };
        };
      };
  };
}

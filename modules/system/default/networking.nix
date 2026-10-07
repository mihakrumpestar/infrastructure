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

          # systemd-resolved is NetBird's supported Linux DNS backend (per-link
          # DNS and split domains over D-Bus). On NetworkManager hosts this also
          # switches NM to dns=systemd-resolved; on systemd-networkd hosts the
          # networkd module already enables it.
          #
          # The stub listener is pinned on. It only ever binds loopback
          # (127.0.0.53 and 127.0.0.54), never a wildcard or a public interface,
          # so it never exposes DNS on the network. A local resolver bound to a
          # specific address still coexists; only a wildcard :53 bind can clash.
          # Check: resolvectl status, ss -lunp | grep :53
          services.resolved = {
            enable = true;
            settings.Resolve.DNSStubListener = true;
          };

          # NetBird mesh VPN client (WireGuard-based). https://docs.netbird.io
          # The client key "netbird" keeps the canonical names: netbird.service,
          # the netbird/netbird-ui CLIs and the "netbird" socket group.
          # Hardened (module default) runs the daemon as a dedicated user and
          # restricts its control socket to the "netbird" group; interactive
          # users join that group in modules/users. Authenticate with
          # `netbird up` (SSO). Set useRoutingFeatures to "client"/"server"/
          # "both" when using exit nodes, network routes or this host as a
          # routing peer.
          services.netbird = {
            # netbird-ui only where a graphical session exists
            ui.enable = config.services.displayManager.sessionPackages != [ ] || config.services.xserver.enable;

            clients.netbird = {
              port = 51820;
              interface = "wt0";
              openFirewall = true;
              openInternalFirewall = true;
            };
          };

          networking = {
            useDHCP = false;
            firewall.enable = true;
            nftables.enable = true;
          };

          boot.kernel.sysctl = {
            # Enable IP forwarding for NetBird, kubernetes, and VMs
            "net.ipv4.ip_forward" = true; # Verify: "cat /proc/sys/net/ipv4/ip_forward" or "sysctl net.ipv4.ip_forward"
            "net.ipv6.conf.all.forwarding" = true;

            # For macvlan
            "net.ipv4.conf.all.arp_filter" = true;
            "net.ipv4.conf.all.rp_filter" = true;

            # Enable local routing
            "net.ipv4.conf.all.route_localnet" = true;

            # Optimistic memory allocation (eg. for Redis, Valkey)
            "vm.overcommit_memory" = lib.mkDefault 1;

            # Caddy quic: https://github.com/quic-go/quic-go/wiki/UDP-Buffer-Sizes
            "net.core.rmem_max" = 7500000;
            "net.core.wmem_max" = 7500000;
          };
        };
      };
  };
}

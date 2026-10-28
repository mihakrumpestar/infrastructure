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

          # /etc/resolv.conf follows resolved's uplink list, not the stub.
          # Podman strips loopback nameservers when it builds a container's
          # resolv.conf and, with only the stub left, substitutes hardcoded
          # 8.8.8.8/8.8.4.4. The uplink file lists the resolvers resolved
          # actually uses, so containers inherit them and follow DHCP and
          # NetBird changes with no generated config. resolved rewrites the
          # file in place, so the symlink target stays valid.
          #
          # NetBird discovers its DNS backend with `resolved && (nss-resolve
          # ahead of dns || 127.0.0.53 in resolv.conf)`. With the stub gone it
          # depends on nss-resolve ordering alone, so the assertion below pins
          # it. Without that, NetBird falls to file mode and tries to rewrite
          # this read-only file.
          environment.etc."resolv.conf".source = lib.mkForce "/run/systemd/resolve/resolv.conf";

          assertions = [
            {
              assertion =
                let
                  hosts = config.system.nssDatabases.hosts or [ ];
                  indexOf = name: lib.lists.findFirstIndex (lib.hasPrefix name) (-1) hosts;
                  resolveAt = indexOf "resolve";
                  dnsAt = indexOf "dns";
                in
                resolveAt != -1 && (dnsAt == -1 || resolveAt < dnsAt);
              message = ''
                nss-resolve must precede dns in system.nssDatabases.hosts.
                /etc/resolv.conf points at resolved's uplink list, which drops
                the 127.0.0.53 stub, and NetBird only selects systemd-resolved
                as its DNS backend when nss-resolve is used ahead of dns.
              '';
            }
          ];

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

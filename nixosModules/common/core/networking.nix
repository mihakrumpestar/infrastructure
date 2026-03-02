{
  config,
  vars,
  lib,
  hostName,
  ...
}:
with lib; {
  options.my = {
    networking.homeWifi = {
      enable = mkEnableOption "Provision home wifi credentials on device";
      autoconnect.enable = mkEnableOption "Whether to enable WiFi autoconnect";
    };
  };

  config = {
    # Works only if NetworkManager is enabled
    age.secrets.homeWifi = mkIf config.my.networking.homeWifi.enable {
      file = /${vars.secretsDir}/secrets/users/homeWifi.nmconnection.age;
      path = "/etc/NetworkManager/system-connections/homeWifi.nmconnection";
    };

    # Check: ss -tulnp
    services.resolved.settings.Resolve.DNSStubListener = false;

    networking = {
      inherit hostName;

      useDHCP = false;

      networkmanager.enable = config.my.hostType == "client";
      firewall = {
        enable = true;
      };
      nftables.enable = true;
    };

    # https://wiki.nixos.org/wiki/Systemd/networkd
    # https://astro.github.io/microvm.nix/simple-network.html
    # Test:
    # networkctl
    systemd.network = mkIf (config.my.hostType == "server" && config.my.hostSubType != "vm") {
      enable = true;

      # Bridge
      netdevs = {
        "20-br0" = {
          netdevConfig = {
            Kind = "bridge";
            Name = "br0";
          };
        };
      };
    };

    boot.kernel.sysctl = {
      # Enable IP forwarding for tailscale, kubernetes, and VMs
      "net.ipv4.ip_forward" = true; #  Verify: "cat /proc/sys/net/ipv4/ip_forward" or "sysctl net.ipv4.ip_forward"
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
}

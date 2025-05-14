{
  config,
  pkgs,
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
    # /etc/hosts
    networking.hostFiles = [
      (pkgs.writeText "hosts" config.my.store-secrets.secrets."hosts")
    ];

    # Check: ss -tulnp
    #services.resolved.extraConfig = mkIf config.my.server.enable ''
    #  DNSStubListener=no
    #''; # Prevent listening on port 53 which is needed for self hosted DNS server

    networking = {
      inherit hostName;
      useDHCP = !config.my.server.enable && !config.my.client.enable;
      #dhcpcd.enable = !config.my.server.enable;

      networkmanager.enable = config.my.client.enable;
      firewall = {
        enable = !config.my.server.enable;
        trustedInterfaces = mkIf config.my.server.enable ["virbr0" "br0" "br1"];
        # TODO: not working
        extraInputRules = ''
          # Allow incoming traffic on our bridge interfaces.
          iifname "br0" accept
          iifname "br1" accept
          iifname "virbr0" accept

          # Allow traffic on any interface starting with "vnet"
          #iifname ~ "^vnet" accept
          iifname { "vnet0", "vnet1", "vnet2", "vnet3", "vnet4" } accept
        '';

        extraForwardRules = ''
          # Allow forwarding for traffic coming from or going to the bridge interfaces.
          iifname "br0" accept
          oifname "br0" accept
          iifname "br1" accept
          oifname "br1" accept
          iifname "virbr0" accept
          oifname "virbr0" accept

          # Allow forwarded traffic on any interface starting with "vnet"
          #iifname ~ "^vnet" accept
          #oifname ~ "^vnet" accept
          iifname { "vnet0", "vnet1", "vnet2", "vnet3", "vnet4" } accept
          oifname { "vnet0", "vnet1", "vnet2", "vnet3", "vnet4" } accept
        '';
      };
      nftables.enable = true; # Warning: incompatible regular Docker
    };

    # https://nixos.wiki/wiki/Systemd-networkd
    # https://astro.github.io/microvm.nix/simple-network.html
    systemd.network = mkIf config.my.server.enable {
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

      networks = {
        # Bridge
        "40-br0" = {
          matchConfig.Name = "br0";
          networkConfig = {
            # Address = [ "10.0.0.66/16" ]; # Set in host/configuration.nix
            Gateway = ["10.0.0.1"];
            DNS = ["9.9.9.9" "1.1.1.1"];
            #IPv4Forwarding = true;
          };
          linkConfig.RequiredForOnline = "carrier";
        };
        "30-pcie0" = {
          matchConfig.Name = "pcie0";
          networkConfig.Bridge = "br0";
          linkConfig.RequiredForOnline = "enslaved";
        };

        # Standalone NIC
        "40-nic0" = {
          matchConfig.Name = "nic0";
          networkConfig = {
            # Address = [ "10.0.0.66/16" ]; # Set in host/configuration.nix
            Gateway = ["10.0.0.1"];
            DNS = ["9.9.9.9" "1.1.1.1"];
          };
          linkConfig.RequiredForOnline = "routable";
        };

        # Make Docker work
        "19-docker" = {
          matchConfig.Name = "veth*";
          linkConfig.Unmanaged = true;
        };
      };
    };

    boot.kernel.sysctl = {
      # Enable IP forwarding for tailscale, kubernetes, and VMs
      "net.ipv4.ip_forward" = true; #  Verify: cat /proc/sys/net/ipv4/ip_forward
      "net.ipv6.conf.all.forwarding" = true;

      # For macvlan
      "net.ipv4.conf.all.arp_filter" = true;
      "net.ipv4.conf.all.rp_filter" = true;
    };

    sops = let
      ssid = config.my.store-secrets.secrets.homeWifi_ssid;
    in
      mkIf config.my.networking.homeWifi.enable
      {
        templates = {
          "${ssid}.nmconnection" = {
            path = "/etc/NetworkManager/system-connections/${ssid}.nmconnection";
            content = ''
              [connection]
              id=${ssid}
              uuid=7a4e0da3-8cf7-49cc-947f-b938fffc681a
              type=wifi
              autoconnect=${
                if config.my.networking.homeWifi.autoconnect.enable
                then "true"
                else "false"
              }

              [wifi]
              mode=infrastructure
              ssid=${ssid}

              [wifi-security]
              key-mgmt=wpa-psk
              psk=${config.sops.placeholder."wireless/${ssid}/psk"}

              [ipv4]
              method=auto

              [ipv6]
              addr-gen-mode=stable-privacy
              method=auto

              [proxy]
            '';
          };
        };

        secrets = {
          "wireless/${ssid}/psk" = {};
        };
      };
  };
}

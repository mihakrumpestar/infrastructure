{
  pkgs,
  consul-cni,
  vars,
  ...
}: let
  nodeIPAddress = "10.0.30.10";
in {
  my = {
    disks = {
      bootDisk = "/dev/sda";
      swapSize = "32G";
      encryptRoot = "tpm2";
    };

    hostType = "server";

    hardware.nvidia.enable = true;
  };

  systemd.network = {
    networks = {
      "40-br0".networkConfig.Address = ["${nodeIPAddress}/16"];
      "40-nic0".networkConfig.Address = ["10.0.30.15/16"];
    };

    links = {
      "20-pcie0" = {
        matchConfig.PermanentMACAddress = "c0:a2:b6:a6:21:29";
        linkConfig.Name = "pcie0";
      };
      "20-nic0" = {
        matchConfig.PermanentMACAddress = "2c:f0:5d:21:57:d7";
        linkConfig.Name = "nic0";
      };
    };
  };

  # mkfs.xfs -L data-01 /dev/nvme0n1p1
  # ls -l /dev/disk/by-label/
  fileSystems."/mnt/data-01" = {
    device = "/dev/disk/by-label/data-01";
    fsType = "xfs";
    options = [
      "defaults"
      "noatime" # Reduces writes, improves performance
      "discard" # Enables TRIM for NVMe
      "logbsize=256k" # Larger log buffer for better throughput
    ];
  };

  networking.firewall = {
    allowedTCPPorts = [53 443 4646 8500]; # DNS and UIs
    allowedUDPPorts = [53 443 4646 8500]; # DNS and UIs
    # Nomad dynamic ports
    allowedTCPPortRanges = [
      {
        from = 20000;
        to = 32000;
      }
    ];
    allowedUDPPortRanges = [
      {
        from = 20000;
        to = 32000;
      }
    ];
  };

  systemd.services.consul.serviceConfig = {
    AmbientCapabilities = "CAP_NET_BIND_SERVICE";
    CapabilityBoundingSet = "CAP_NET_BIND_SERVICE";
  };

  networking = {
    firewall = {
      # Allow containers in "nomad" network reach gateway DNS
      extraInputRules = ''
        iifname "nomad" ip daddr 172.26.64.1 tcp dport 53 accept
        iifname "nomad" ip daddr 172.26.64.1 udp dport 53 accept
      '';
    };
  };

  services = {
    # Consul
    consul = {
      enable = true;
      webUi = true;

      forceAddrFamily = "ipv4"; # Use IPv4 only

      extraConfig = {
        server = true;
        datacenter = "dc1";

        log_level = "warn"; # "trace", "debug", "info", "warn", and "error".

        bootstrap_expect = 1; # Will change to 3 for 3-node cluster
        bind_addr = "0.0.0.0"; # Internal
        client_addr = "${nodeIPAddress} 127.0.0.1"; # Connectable IP
        advertise_addr = nodeIPAddress;
        ports = {
          dns = 8600;
          http = 8500;
          grpc = 8502; # Has to be enabled for Consul Connect service mesh
        };

        connect = {
          enabled = true; # Enable Consul Connect service mesh
        };

        recursors = ["9.9.9.9" "1.1.1.1"];
      };
    };

    # Nomad
    nomad = {
      enable = true;
      extraPackages = with pkgs; [consul dmidecode];
      extraSettingsPlugins = with pkgs; [nomad-driver-podman];
      enableDocker = false;
      dropPrivileges = false; # Required for Podman driver

      settings = {
        datacenter = "dc1";
        bind_addr = "0.0.0.0";

        log_level = "WARN"; # WARN, INFO, DEBUG, or TRACE

        # Explicitly advertise reachable addresses to other nodes
        advertise = {
          http = "${nodeIPAddress}:4646";
          rpc = "${nodeIPAddress}:4647";
          serf = "${nodeIPAddress}:4648";
        };

        server = {
          enabled = true;
          bootstrap_expect = 1; # Will change to 3 for 3-node cluster
        };

        client = {
          enabled = true;
          cni_path = "${pkgs.cni-plugins}/bin:${consul-cni}/bin"; # This is by default hardcoded, so in NixOS it does not work, this is a workaround
          # For single node, only itself. For 3-node, list ALL server IPs
          servers = ["${nodeIPAddress}:4647"];
          meta = {
            NOMAD_CLIENT_IP = nodeIPAddress;
          };
        };

        # Consul Integration
        consul = {
          address = "127.0.0.1:8500";
          grpc_address = "127.0.0.1:8502";
          server_service_name = "nomad";
          client_service_name = "nomad-client";
          auto_advertise = true;
          server_auto_join = true;
          client_auto_join = true;
        };

        plugin = [
          {
            nomad-driver-podman = {
              # Needs to be present to be enabled ("nomad-driver-podman")
              config = {
                auth = {
                  config = "/etc/containers/auth.json";
                };
                socket_path = "unix:///run/podman/podman.sock";
              };
            };
          }
        ];
      };
    };
  };

  age.secrets.containers_auth_json = {
    file = /${vars.secretsDir}/secrets/users/containers_auth.json.age;
    path = "/etc/containers/auth.json";
  };
}

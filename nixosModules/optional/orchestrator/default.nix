{
  pkgs,
  consul-cni,
  vars,
  lib,
  config,
  ...
}:
with lib; let
  cfg = config.my.orchestrator;
in {
  options.my.orchestrator = {
    enable = mkEnableOption "Orchestrator cluster";

    nodeIPAddress = lib.mkOption {
      type = lib.types.strMatching "^([0-9]{1,3}\\.){3}[0-9]{1,3}$";
      example = "10.0.0.5";
      description = "IP address that Nomad and Consul bind to, as well as advertise to other nodes";
    };
  };

  config = mkIf cfg.enable {
    networking.firewall = {
      allowedTCPPorts = [443 4646 8500]; # UIs
      allowedUDPPorts = [443 4646 8500]; # UIs
      # Nomad dynamic ports
      #allowedTCPPortRanges = [
      #  {
      #    from = 20000;
      #    to = 32000;
      #  }
      #];
      #allowedUDPPortRanges = [
      #  {
      #    from = 20000;
      #    to = 32000;
      #  }
      #];

      interfaces.br0 = {
        allowedTCPPorts = [53 5353]; # DNS
        allowedUDPPorts = [53 5353]; # DNS
      };
    };

    systemd.services.consul.serviceConfig = {
      AmbientCapabilities = "CAP_NET_BIND_SERVICE";
      CapabilityBoundingSet = "CAP_NET_BIND_SERVICE";
    };

    networking = {
      firewall = {
        # Allow containers in "nomad" network reach gateway DNS for Consul
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
          client_addr = "${cfg.nodeIPAddress} 127.0.0.1"; # Connectable IP
          advertise_addr = cfg.nodeIPAddress;
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
            http = "${cfg.nodeIPAddress}:4646";
            rpc = "${cfg.nodeIPAddress}:4647";
            serf = "${cfg.nodeIPAddress}:4648";
          };

          server = {
            enabled = true;
            bootstrap_expect = 1; # Will change to 3 for 3-node cluster
          };

          client = {
            enabled = true;
            cni_path = "${pkgs.cni-plugins}/bin:${consul-cni}/bin"; # This is by default hardcoded, so in NixOS it does not work, this is a workaround
            # For single node, only itself. For 3-node, list ALL server IPs
            servers = ["${cfg.nodeIPAddress}:4647"];
            meta = {
              NOMAD_CLIENT_IP = cfg.nodeIPAddress;
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

    services.coredns = {
      enable = true;
      config = ''
        .:53 {
          bind ${cfg.nodeIPAddress} 127.0.0.1

          forward . ${cfg.nodeIPAddress}:5353 9.9.9.9 1.1.1.1 {
            policy sequential
            failover SERVFAIL REFUSED
          }

          #log
          errors
        }

        .:53 {
          bind 172.26.64.1

          forward . 127.0.0.1:8600

          #log
          errors
        }
      '';
    };

    systemd.services.coredns = {
      # default "network.target" is not good enough
      after = lib.mkForce [
        "network-online.target"
        "nomad.service" # Wait for Nomad service to be active
      ];
      wants = [
        "network-online.target"
        "nomad.service"
      ];
      serviceConfig = {
        RestartSec = "5s"; # Give Nomad time to create IP (takes about 13 seconds)
        StartLimitIntervalSec = 120;
        StartLimitBurst = 30; # Allow many retries initially
      };
    };
  };
}

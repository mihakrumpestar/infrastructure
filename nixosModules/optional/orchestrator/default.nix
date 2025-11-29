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
      allowedTCPPorts = [53 443 4646 8500]; # DNS, UIs
      allowedUDPPorts = [53 443 4646 8500]; # DNS, UIs
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
        allowedTCPPorts = [30010]; # Registry
        allowedUDPPorts = [30010]; # Registry
      };
    };

    networking = {
      firewall = {
        # Don't know why connections to Consul DNS appear as they are from Nomad interface, even tho we use CoreDNS
        extraInputRules = ''
          iifname "nomad" ip daddr ${cfg.nodeIPAddress} tcp dport 8600 accept
          iifname "nomad" ip daddr ${cfg.nodeIPAddress} udp dport 8600 accept
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

          recursors = ["127.0.0.1"]; # Redirects to Blocky in Nomad, othervise to regular DNS

          limits = {
            http_max_conns_per_client = 10000; # Default is 200 and we start getting: "Missing: health.service..."
          };
        };
      };

      # Nomad
      nomad = {
        enable = true;
        extraPackages = with pkgs; [consul dmidecode];
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
            network_interface = "br0";

            host_network = [
              {
                "default" = {
                  interface = "br0";
                };
              }
              {
                "lo" = {
                  interface = "lo";
                };
              }
              {
                "public" = {
                  interface = "br0";
                };
              }
            ];

            reserved.reserved_ports = "22222"; # SSH

            cni_path = "${pkgs.cni-plugins}/bin:${consul-cni}/bin"; # This is by default hardcoded, so in NixOS it does not work, this is a workaround
            cni_config_dir = "/etc/cni/config"; # Default is /opt/cni/config
            servers = ["${cfg.nodeIPAddress}:4647"]; # For single node, only itself. For 3-node, list ALL server IPs
            meta = {
              #NOMAD_CLIENT_IP = cfg.nodeIPAddress;
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

          telemetry = {
            collection_interval = "1s";
            disable_hostname = true;
            prometheus_metrics = true;
            publish_allocation_metrics = true;
            publish_node_metrics = true;
          };

          plugin = [
            {
              docker = {
                config = {
                  allow_privileged = true;
                  allow_caps = [
                    "audit_write"
                    "chown"
                    "dac_override"
                    "fowner"
                    "fsetid"
                    "kill"
                    "mknod"
                    "net_bind_service"
                    "setfcap"
                    "setgid"
                    "setpcap"
                    "setuid"
                    "sys_chroot"
                    # Added to default
                    "net_raw"
                    "sys_time"
                    "net_admin"
                    "sys_module"
                  ];

                  auth = {
                    config = "/etc/containers/auth.json";
                  };

                  # https://github.com/grafana/loki/issues/6165
                  extra_labels = ["*"];
                  logging = {
                    type = "journald";
                    config = {
                      tag = "nomad";
                      labels-regex = "com\\.hashicorp\\.nomad.*";
                    };
                  };

                  volumes = {
                    enabled = true;
                  };
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

    # TODO: In testing
    environment.etc."cni/config/lan.conflist".text = ''
      {
        "cniVersion": "0.4.0",
        "name": "lan",
        "plugins": [
          {
            "type": "loopback"
          },
          {
            "type": "bridge",
            "bridge": "br0",
            "isGateway": false,
            "ipMasq": false,
            "hairpinMode": false,
            "ipam": {
              "type": "host-local",
              "routes": [{ "dst": "0.0.0.0/0" }],
              "ranges": [
                [
                  {
                    "subnet": "10.0.0.0/16",
                    "rangeStart": "10.0.30.200",
                    "rangeEnd": "10.0.30.254",
                    "gateway": "10.0.0.1"
                  }
                ]
              ]
            }
          }
        ]
      }
    '';

    services.coredns = {
      enable = true;

      # The following config makes only DNS request from localhost reach Consul DNS, others go to Blocky
      config = ''
        .:53 {
          bind ${cfg.nodeIPAddress}

          view nomad {
              # Match queries originating from the nomad interface subnet (they connect from localhost)
              expr incidr(client_ip(), '127.0.0.1/8')
          }

          # Forward these queries to Consul DNS
          forward . 127.0.0.1:8600

          #log
          errors
        }

        .:53 {
          bind ${cfg.nodeIPAddress} 127.0.0.1

          forward . 127.0.0.1:5353 9.9.9.9 1.1.1.1 {
            force_tcp # HAProxy can't do UDP
            policy sequential
            failfast_all_unhealthy_upstreams
            failover SERVFAIL REFUSED
          }

          #log
          errors
        }
      '';
    };

    # Wait for br0 IP to be online
    systemd.services.coredns = {
      startLimitIntervalSec = 120;
      startLimitBurst = 30;

      # default "network.target" is not good enough
      after = lib.mkForce ["network-online.target"];
      wants = ["network-online.target"];
      serviceConfig = {
        RestartSec = "5s"; # Give Nomad time to create IP (takes about 13 seconds)
      };
    };
  };
}

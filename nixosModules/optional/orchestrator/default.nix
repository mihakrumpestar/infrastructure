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
      allowedTCPPorts = [53 443 4646 8501]; # DNS, UIs
      allowedUDPPorts = [53 443 4646 8501]; # DNS, UIs
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
            http = -1; # Otherwise it stays enabled
            https = 8501;
            #grpc = 8502; # Has to be enabled for Consul Connect service mesh (if TLS is not configured)
            grpc_tls = 8503;
          };

          tls = {
            defaults = {
              ca_file = config.age.secrets."consul-agent-ca_pem".path;
              cert_file = config.age.secrets."dc1-server-consul-0_pem".path;
              key_file = config.age.secrets."dc1-server-consul-0-key_pem".path;

              #tls_min_version = "TLSv1_3"; # DO NOT ENABLE THIS! Envoy does not support TLSv1_3
              verify_incoming = true;
              verify_outgoing = true;
              verify_server_hostname = true;
            };

            grpc = {
              # https://developer.hashicorp.com/nomad/docs/configuration/consul#grpc_ca_file
              verify_incoming = false; # This is ok, as long as we enable ACLs (envoy authenticates using them)
            };
          };

          connect = {
            enabled = true; # Enable Consul Connect service mesh

            ca_provider = "consul";
            ca_config = {
              leaf_cert_ttl = "8760h"; # 1 year
              intermediate_cert_ttl = "26280h"; # 3 years
              root_cert_ttl = "87600h"; # 10 years

              private_key_type = "rsa";
              private_key_bits = "2048";
            };
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

          # This tls part is for server and client
          tls = {
            http = true;
            rpc = true;

            tls_min_version = "tls13";

            ca_file = config.age.secrets."nomad-agent-ca_pem".path;
            cert_file = config.age.secrets."global-server-nomad_pem".path;
            key_file = config.age.secrets."global-server-nomad-key_pem".path;

            verify_server_hostname = true;
            verify_https_client = true;
          };

          client = {
            enabled = true;
            network_interface = "br0";
            preferred_address_family = "ipv4";

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

              # https://developer.hashicorp.com/nomad/docs/job-specification/sidecar_task#log_level
              "connect.log_level" = "warning"; # trace, debug, info, warning/warn, error, critical, off
            };
          };

          # Consul Integration
          consul = {
            address = "127.0.0.1:8501";
            grpc_address = "127.0.0.1:8503";

            ca_file = config.age.secrets."consul-agent-ca_pem".path;
            cert_file = config.age.secrets."dc1-client-consul-0_pem".path;
            key_file = config.age.secrets."dc1-client-consul-0-key_pem".path;

            grpc_ca_file = config.age.secrets."consul-agent-ca_pem".path;

            ssl = true;
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

    systemd.services = {
      consul = {
        serviceConfig = {
          RestartSec = 2; # Give time to decrypt, Nomad already has this
        };
      };
    };

    age.secrets = {
      "consul-agent-ca_pem" = {
        file = /${vars.secretsDir}/secrets/consul/consul-agent-ca.pem.age;
        owner = "consul";
        group = "consul";
      };
      "dc1-server-consul-0_pem" = {
        file = /${vars.secretsDir}/secrets/consul/dc1-server-consul-0.pem.age;
        owner = "consul";
        group = "consul";
      };
      "dc1-server-consul-0-key_pem" = {
        file = /${vars.secretsDir}/secrets/consul/dc1-server-consul-0-key.pem.age;
        owner = "consul";
        group = "consul";
      };
      "dc1-client-consul-0_pem" = {
        file = /${vars.secretsDir}/secrets/consul/dc1-client-consul-0.pem.age;
        owner = "consul";
        group = "consul";
      };
      "dc1-client-consul-0-key_pem" = {
        file = /${vars.secretsDir}/secrets/consul/dc1-client-consul-0-key.pem.age;
        owner = "consul";
        group = "consul";
      };

      "nomad-agent-ca_pem".file = /${vars.secretsDir}/secrets/nomad/nomad-agent-ca.pem.age;
      "global-server-nomad_pem".file = /${vars.secretsDir}/secrets/nomad/global-server-nomad.pem.age;
      "global-server-nomad-key_pem".file = /${vars.secretsDir}/secrets/nomad/global-server-nomad-key.pem.age;
      "global-client-nomad_pem".file = /${vars.secretsDir}/secrets/nomad/global-client-nomad.pem.age;
      "global-client-nomad-key_pem".file = /${vars.secretsDir}/secrets/nomad/global-client-nomad-key.pem.age;

      "containers_auth_json" = {
        file = /${vars.secretsDir}/secrets/users/containers_auth.json.age;
        path = "/etc/containers/auth.json";
      };
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

    systemd.services.coredns = {
      serviceConfig = {
        RestartSec = 2;
      };
    };
  };
}

{ inputs, ... }:
let
  secretsDir = inputs.infrastructure-secrets;
in
{
  den.aspects.orchestrator-nomad = {
    nixos =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        cfg = config.my.orchestrator;
      in
      {
        config = {
          networking.firewall = {
            allowedTCPPorts = [
              443
              4646
            ];
            allowedUDPPorts = [
              443
              4646
            ];
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

            #interfaces.br0 = {
            #  allowedTCPPorts = [30010]; # Registry
            #  allowedUDPPorts = [30010]; # Registry
            #};
          };

          services.nomad = {
            enable = true;
            extraPackages = with pkgs; [
              consul
              dmidecode
            ];
            dropPrivileges = false; # Required for Podman driver

            settings = {
              datacenter = "dc1";
              bind_addr = "0.0.0.0";

              log_level = "WARN"; # WARN, INFO, DEBUG, or TRACE

              # Explicitly advertise reachable addresses to other nodes
              advertise = {
                http = "${cfg.bindAddress}:4646";
                rpc = "${cfg.bindAddress}:4647";
                serf = "${cfg.bindAddress}:4648";
              };

              server = {
                enabled = true;
                bootstrap_expect = 1; # Will change to 3 for 3-node cluster
              };

              # ACLs
              acl = {
                enabled = true;
                token_ttl = "24h"; # More frequent rotation
                policy_ttl = "30s"; # Faster policy updates
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
                verify_https_client = true; # mTLS for all HTTPS endpoints
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

                reserved.reserved_ports = lib.concatStringsSep "," (map toString config.services.openssh.ports); # SSH

                cni_path = "${pkgs.cni-plugins}/bin:${pkgs.consul-cni}/bin"; # This is by default hardcoded, so in NixOS it does not work, this is a workaround
                cni_config_dir = "/etc/cni/config"; # Default is /opt/cni/config
                servers = [ "${cfg.bindAddress}:4647" ]; # For single node, only itself. For 3-node, list ALL server IPs
                meta = {
                  #NOMAD_CLIENT_IP = cfg.bindAddress;

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

                # Workload Identity - allows Nomad tasks/services to authenticate to Consul
                # Requires Consul auth method to be configured (see README)
                service_identity = {
                  aud = [ "consul.io" ];
                  ttl = "1h";
                };
                task_identity = {
                  aud = [ "consul.io" ];
                  ttl = "1h";
                };
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
                      extra_labels = [ "*" ];
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

          age.secrets = {
            "nomad-agent-ca_pem".file = "${secretsDir}/secrets/services/nomad/nomad-agent-ca.pem.age";
            "global-server-nomad_pem".file = "${secretsDir}/secrets/services/nomad/global-server-nomad.pem.age";
            "global-server-nomad-key_pem".file =
              "${secretsDir}/secrets/services/nomad/global-server-nomad-key.pem.age";
            "global-client-nomad_pem".file = "${secretsDir}/secrets/services/nomad/global-client-nomad.pem.age";
            "global-client-nomad-key_pem".file =
              "${secretsDir}/secrets/services/nomad/global-client-nomad-key.pem.age";

            "containers_auth_json" = {
              file = "${secretsDir}/secrets/users/containers_auth.json.age";
              path = "/etc/containers/auth.json";
            };
          };

          # TODO: In testing, does not work
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

          #services.iperf3 = {
          #  enable = true;
          #  openFirewall = true;
          #  bind = cfg.bindAddress;
          #};

          virtualisation.docker.daemon.settings.dns = [ "${cfg.bindAddress}" ];
        };
      };
  };
}

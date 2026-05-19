{ inputs, ... }:
let
  secretsDir = inputs.infrastructure-secrets;
in
{
  den.aspects.orchestrator-consul = {
    nixos =
      {
        config,
        ...
      }:
      let
        cfg = config.my.orchestrator;
      in
      {
        config = {
          networking.firewall = {
            allowedTCPPorts = [ 8501 ];
            allowedUDPPorts = [ 8501 ];

            # Don't know why connections to Consul DNS appear as they are from Nomad interface, even tho we use CoreDNS
            extraInputRules = ''
              iifname "nomad" ip daddr ${cfg.nodeIPAddress} tcp dport 8600 accept
              iifname "nomad" ip daddr ${cfg.nodeIPAddress} udp dport 8600 accept
            '';
          };

          services.consul = {
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
                #grpc = 8502; # Has to be enabled for Consul Connect service mesh (if TLS is NOT configured)
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

                # https://developer.hashicorp.com/consul/commands/connect/ca
                # Only applys on init, after that you have to use the following command:
                # consul connect ca set-config -config-file=tmp.json
                /*
                  {
                    "Provider": "consul",
                    "Config": {
                      "IntermediateCertTTL": "26280h",
                      "LeafCertTTL": "8760h",
                      "RootCertTTL": "87600h",
                      "PrivateKeyType": "rsa",
                      "PrivateKeyBits": 2048
                    }
                  }
                */

                ca_provider = "consul";
                ca_config = {
                  leaf_cert_ttl = "8760h"; # 1 year
                  intermediate_cert_ttl = "26280h"; # 3 years
                  root_cert_ttl = "87600h"; # 10 years

                  private_key_type = "rsa";
                  private_key_bits = 2048;
                };
              };

              recursors = [ "127.0.0.1" ]; # Redirects to Blocky in Nomad, othervise to regular DNS

              limits = {
                http_max_conns_per_client = 10000; # Default is 200 and we start getting: "Missing: health.service..."
              };

              # ACLs
              acl = {
                enabled = true;
                default_policy = "deny";
                enable_token_persistence = true;
              };
            };
          };

          systemd.services.consul.serviceConfig.RestartSec = 2; # Give time to decrypt, Nomad already has this in nixpkgs service

          age.secrets = {
            "consul-agent-ca_pem" = {
              rekeyFile = "${secretsDir}/secrets/services/consul/consul-agent-ca.pem.age";
              owner = "consul";
              group = "consul";
            };
            "dc1-server-consul-0_pem" = {
              rekeyFile = "${secretsDir}/secrets/services/consul/dc1-server-consul-0.pem.age";
              owner = "consul";
              group = "consul";
            };
            "dc1-server-consul-0-key_pem" = {
              rekeyFile = "${secretsDir}/secrets/services/consul/dc1-server-consul-0-key.pem.age";
              owner = "consul";
              group = "consul";
            };
            "dc1-client-consul-0_pem" = {
              rekeyFile = "${secretsDir}/secrets/services/consul/dc1-client-consul-0.pem.age";
              owner = "consul";
              group = "consul";
            };
            "dc1-client-consul-0-key_pem" = {
              rekeyFile = "${secretsDir}/secrets/services/consul/dc1-client-consul-0-key.pem.age";
              owner = "consul";
              group = "consul";
            };
          };
        };
      };
  };
}

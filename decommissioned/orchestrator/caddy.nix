{ ... }:
{
  den.aspects.orchestrator-caddy = {
    nixos =
      { config, pkgs, ... }:
      {
        config = {
          # Caddy reverse proxy for Nomad JWKS endpoint
          # Exposes JWKS without requiring client certificates (for Consul workload identity)
          services.caddy = {
            enable = true;
            user = "root";
            group = "root";
            configFile = pkgs.writeText "Caddyfile" ''
               {
                 admin off
               }

               http://127.0.0.1:4649 {
                 @jwks path /.well-known/jwks.json
                 handle @jwks {
                   reverse_proxy https://127.0.0.1:4646 {
                    transport http {
                      tls
                      tls_client_auth ${config.age.secrets."global-client-nomad_pem".path} ${
                        config.age.secrets."global-client-nomad-key_pem".path
                      }
                      tls_trust_pool file ${config.age.secrets."nomad-agent-ca_pem".path}
                    }
                  }
                }
                respond 404
              }
            '';
          };
        };
      };
  };
}

{ ... }:
{
  den.aspects.orchestrator-coredns = {
    nixos =
      { config, lib, ... }:
      let
        cfg = config.my.orchestrator;
        dnsPorts = lib.optionals cfg.publicDns [ 53 ];
      in
      {
        config = {
          networking.firewall = {
            allowedTCPPorts = dnsPorts; # DNS (conditional)
            allowedUDPPorts = dnsPorts; # DNS (conditional)
          };

          services.coredns = {
            enable = true;

            # The following config makes only DNS request from localhost reach Consul DNS, others go to Blocky
            config = ''
              .:53 {
                bind ${cfg.nodeIPAddress}

                view nomad {
                    # Match queries originating from the nomad interface subnet (they connect from nomad IP range)
                    expr incidr(client_ip(), '172.26.64.1/20')
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

          systemd.services.coredns.serviceConfig.RestartSec = 2;
        };
      };
  };
}

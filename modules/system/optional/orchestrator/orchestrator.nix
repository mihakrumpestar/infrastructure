{ den, ... }:
{
  den.aspects.orchestrator = {
    includes = [
      den.aspects.containers
      den.aspects.orchestrator-consul
      den.aspects.orchestrator-nomad
      den.aspects.orchestrator-coredns
      den.aspects.orchestrator-caddy
    ];

    nixos =
      { lib, ... }:

      {
        options.my.orchestrator = {
          nodeIPAddress = lib.mkOption {
            type = lib.types.strMatching "^([0-9]{1,3}\\.){3}[0-9]{1,3}$";
            example = "10.0.0.5";
            description = "IP address that Nomad and Consul bind to, as well as advertise to other nodes";
          };

          publicDns = lib.mkEnableOption "public DNS access on port 53";
        };
      };
  };
}

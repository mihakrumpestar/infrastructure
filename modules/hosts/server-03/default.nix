{ den, inputs, ... }:
let
  data = import "${inputs.infrastructure-secrets}/secrets/data.nix";
  host = data.hosts.server-03;
in
{
  den.aspects.server-03 = {
    includes = [
      den.aspects.server
      #den.aspects.orchestrator
    ];
    nixos =
      { ... }:
      {
        /*
          Hardware:
            Wyse 5070 Thin Client
            Intel Celeron J4105
            16 GB RAM
            960 GB SATA SSD - boot and data
        */

        imports = [ ./_hardware-configuration.nix ];

        my = {
          disks = {
            bootDisk = "/dev/sda";
            swapSize = "16G";
            encryptRoot = "tpm2";
            bootLoader = "systemd-boot"; # BIOS v1.5 broke third-party Secure Boot (even as enabled in BIOS, reports as being disabled in system)
            #pcrlockSupport = false; # "systemd-pcrlock is-supported" returns "obsolete"
          };

          server.networking = {
            bridges.br0 = {
              inherit (host.nics.default) ip cidr;
              members.nic0.mac = host.nics.default.mac;
            };
          };

          /*
            orchestrator = {
              publicDns = true;
              bindAddress = host.nics.default.ip;
            };
          */
        };
      };
  };
}

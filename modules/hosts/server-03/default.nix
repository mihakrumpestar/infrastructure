{ den, ... }:
{
  den.aspects.server-03 = {
    includes = [
      den.aspects.server
      den.aspects.orchestrator
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
            pcrlockSupport = false; # "systemd-pcrlock is-supported" returns "obsolete"
          };

          server.networking = {
            nodeIPAddress = "10.0.30.30";
            nics = [
              {
                name = "nic0";
                mac = "6c:2b:59:5b:49:85";
              }
            ];
          };

          orchestrator = {
            publicDns = true;
            nodeIPAddress = "10.0.30.30";
          };
        };
      };
  };
}

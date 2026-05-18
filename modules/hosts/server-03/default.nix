{ den, ... }:
let
  networkConfig = {
    Gateway = [ "10.0.0.1" ];
    DNS = [
      "9.9.9.9"
      "1.1.1.1"
    ];
  };
in
{
  den.aspects.server-03 = {
    includes = [
      den.aspects.server
      den.aspects.orchestrator
    ];
    nixos =
      { ... }:
      let
        nodeIPAddress = "10.0.30.30";
      in
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

          orchestrator = {
            publicDns = true;
            inherit nodeIPAddress;
          };
        };

        systemd.network = {
          networks = {
            # Bridge
            "40-br0" = {
              matchConfig.Name = "br0";
              networkConfig = networkConfig // {
                Address = [ "${nodeIPAddress}/16" ];
              };
              linkConfig.RequiredForOnline = "routable"; # carrier is not enough, as services require this ip
            };

            # Nic connected to bridge (main)
            "30-nic0" = {
              matchConfig.Name = "nic0";
              networkConfig.Bridge = "br0";
              linkConfig.RequiredForOnline = "enslaved";
            };
          };

          links = {
            "20-nic0" = {
              matchConfig.PermanentMACAddress = "6c:2b:59:5b:49:85";
              linkConfig.Name = "nic0";
            };
          };
        };
      };
  };
}

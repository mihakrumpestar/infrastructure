{vars, ...}: let
  nodeIPAddress = "10.0.30.30";
in {
  /*
  Hardware:
    Wyse 5070 Thin Client
    Intel Celeron J4105
    16 GB RAM
    960 GB SATA SSD - boot and data
  */

  my = {
    disks = {
      bootDisk = "/dev/sda";
      swapSize = "16G";
      encryptRoot = "tpm2";
      pcrlockSupport = false; # "systemd-pcrlock is-supported" returns "obsolete"
    };

    hostType = "server";

    orchestrator = {
      enable = true;
      publicDns = true;
      inherit nodeIPAddress;
    };
  };

  systemd.network = {
    networks = {
      # Bridge
      "40-br0" = {
        matchConfig.Name = "br0";
        networkConfig = vars.networkConfig // {Address = ["${nodeIPAddress}/16"];};
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
}

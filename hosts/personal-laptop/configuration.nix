{
  my = {
    disks = {
      bootLoader = "lanzaboote";
      bootDisk = "/dev/nvme0n1";
      swapSize = "16G";
      encryptRoot = "fido2";
    };

    impermanence.enable = true;

    hostType = "client";

    networking.homeWifi.enable = true;

    de.plasma.enable = true;

    users = ["krumpy-miha"];
  };
}

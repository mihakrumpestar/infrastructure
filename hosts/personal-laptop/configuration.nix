{
  my = {
    disks = {
      bootDisk = "/dev/nvme0n1";
      swapSize = "16G";
      encryptRoot = "fido2";
    };

    hostType = "client";

    networking.homeWifi.enable = true;

    de.plasma.enable = true;

    users = ["krumpy-miha"];
  };
}

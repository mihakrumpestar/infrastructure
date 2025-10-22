{
  my = {
    disks = {
      bootDisk = "/dev/nvme0n1";
      swapSize = "12G";
      encryptRoot = "fido2";
    };

    hostType = "client";

    networking.homeWifi = {
      enable = true;
      autoconnect.enable = true;
    };

    de.plasma.enable = true;
  };
}

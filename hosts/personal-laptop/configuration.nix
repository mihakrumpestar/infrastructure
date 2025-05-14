{
  my = {
    disks = {
      bootDisk = "/dev/nvme0n1";
      swapSize = "12G";
      encryptRoot = true;
    };

    client.enable = true;
    client.laptop.enable = true;

    networking.homeWifi = {
      enable = true;
      autoconnect.enable = true;
    };

    de.plasma.enable = true;
  };
}

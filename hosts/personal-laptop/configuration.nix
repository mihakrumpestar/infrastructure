{
  /*
  Hardware:
    HP 255 15.6 inch G10 Notebook PC
    AMD Ryzen 5 7530U
    16 GB RAM
    512 GB NVMe SSD
  */

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

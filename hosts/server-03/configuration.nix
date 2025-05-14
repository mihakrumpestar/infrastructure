{
  my = {
    disks = {
      bootDisk = "/dev/sda";
      swapSize = "32G";
      encryptRoot = false;
    };

    server.enable = true;
  };

  systemd.network = {
    networks = {
      "40-nic0".networkConfig.Address = ["10.0.100.30/16"];
      "40-br0".networkConfig.Address = ["10.0.100.35/16"];
    };

    links = {
      "20-nic0" = {
        matchConfig.PermanentMACAddress = "00:e2:69:70:3e:58";
        linkConfig.Name = "nic0";
      };
      "20-pcie0" = {
        matchConfig.PermanentMACAddress = "38:ea:a7:13:cd:80";
        linkConfig.Name = "pcie0";
      };
    };
  };

  fileSystems."/mnt/data" = {
    device = "/dev/disk/by-label/data-01";
    fsType = "xfs";
    neededForBoot = false;
    options = [
      "defaults"
      "discard" # Enable trim for SSDs
    ];
  };
}

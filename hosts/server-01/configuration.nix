let
  nodeIPAddress = "10.0.30.10";
in {
  my = {
    disks = {
      bootDisk = "/dev/sda";
      swapSize = "32G";
      encryptRoot = "tpm2";
    };

    hostType = "server";

    orchestrator = {
      enable = true;
      inherit nodeIPAddress;
    };
    hardware.nvidia.enable = false;
  };

  systemd.network = {
    networks = {
      "40-br0".networkConfig.Address = ["${nodeIPAddress}/16"];
      "40-nic0".networkConfig.Address = ["10.0.30.15/16"];
    };

    links = {
      "20-pcie0" = {
        matchConfig.PermanentMACAddress = "c0:a2:b6:a6:21:29";
        linkConfig.Name = "pcie0";
      };
      "20-nic0" = {
        matchConfig.PermanentMACAddress = "2c:f0:5d:21:57:d7";
        linkConfig.Name = "nic0";
      };
    };
  };

  # mkfs.xfs -L data-01 /dev/nvme0n1p1
  # ls -l /dev/disk/by-label/
  fileSystems."/mnt/data-01" = {
    device = "/dev/disk/by-label/data-01";
    fsType = "xfs";
    options = [
      "defaults"
      "noatime" # Reduces writes, improves performance
      "discard" # Enables TRIM for NVMe
      "logbsize=256k" # Larger log buffer for better throughput
    ];
  };
}

{ den, ... }:
{
  den.aspects.server-01 = {
    includes = [
      den.aspects.server
      den.aspects.orchestrator
    ];
    nixos =
      { ... }:
      {
        /*
          Hardware:
            MS-7B89 (1.0)
            AMD Ryzen 7 5700G
            64 GB RAM
            480 GB SATA SSD - boot
            2 TB NVMe SSD - data
        */

        imports = [ ./_hardware-configuration.nix ];

        my = {
          disks = {
            bootDisk = "/dev/sda";
            swapSize = "32G";
            encryptRoot = "tpm2";
          };

          server.networking = {
            nodeIPAddress = "10.0.30.10";
            nics = [
              {
                name = "pcie0";
                mac = "c0:a2:b6:a6:21:29";
              }
            ];
            standaloneNics = [
              {
                name = "nic0";
                mac = "2c:f0:5d:21:57:d7";
                address = "10.0.30.15/16";
              }
            ];
          };

          orchestrator = {
            publicDns = true;
            nodeIPAddress = "10.0.30.10";
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
      };
  };
}

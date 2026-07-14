{ den, inputs, ... }:
let
  data = import "${inputs.infrastructure-secrets}/secrets/data.nix";
  host = data.hosts.server-01;
in
{
  den.aspects.server-01 = {
    includes = [
      den.aspects.server
      #den.aspects.orchestrator
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
            bridges.br0 = {
              inherit (host.nics.default) ip cidr;
              members.pcie0.mac = host.nics.default.mac;
            };
            standaloneNics = {
              inherit (host.nics) nic0;
            };
          };

          /*
            orchestrator = {
              publicDns = true;
              bindAddress = host.nics.default.ip;
            };
          */
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

        # Nvidia RTX 2080 Ti
        services.xserver.videoDrivers = [ "nvidia" ];
        nixpkgs.config.cudaSupport = true;

        # CUDA binary cache
        nix.settings = {
          substituters = [
            "https://cache.nixos-cuda.org"
          ];
          trusted-public-keys = [
            "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
          ];
        };

        hardware = {
          graphics.enable = true;
          nvidia.open = true;
          #nvidia.nvidiaPersistenced = true; # Keep GPU awake in headless mode
          nvidia-container-toolkit.enable = true; # Verify: podman run --rm --device nvidia.com/gpu=all nvidia/cuda:13.3.0-base-ubuntu24.04 nvidia-smi
        };
      };
  };
}

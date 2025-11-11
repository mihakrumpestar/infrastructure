{
  lib,
  pkgs,
  config,
  ...
}: let
  package_ver = config.boot.kernelPackages.nvidiaPackages.mkDriver rec {
    version = "580.105.08";
    url = "https://us.download.nvidia.com/tesla/${version}/NVIDIA-Linux-x86_64-${version}.run";
    sha256_64bit = "sha256-2cboGIZy8+t03QTPpp3VhHn6HQFiyMKMjRdiV2MpNHU=";
    persistencedSha256 = "";
    fabricmanagerSha256 = "sha256-6zqB0ATeQm3umw8TMgk4KO2xlxJe9XouZQCpXfMzLQs=";
    useSettings = false;
    usePersistenced = true;
    useFabricmanager = true;
  };
in {
  my = {
    disks = {
      bootDisk = "/dev/sda";
      swapSize = "32G";
      encryptRoot = "tpm2";
    };

    hostType = "server";
  };

  systemd.network = {
    networks = {
      "40-br0".networkConfig.Address = ["10.0.30.10/16"];
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

  #fileSystems."/mnt/data" = {
  #  device = "/dev/disk/by-label/data-01";
  #  fsType = "xfs";
  #  neededForBoot = false;
  #  options = [
  #    "defaults"
  #    "discard" # Enable trim for SSDs
  #  ];
  #};

  # Nvidia Tesla GPU support
  hardware = {
    graphics.enable = true;
    nvidia.datacenter.enable = true;
    nvidia.package = package_ver; # config.boot.kernelPackages.nvidiaPackages.dc_535;

    nvidia-container-toolkit.enable = true; # Verify: podman run --rm --device nvidia.com/gpu=all nvidia/cuda:11.0.3-base-ubuntu20.04 nvidia-smi
  };
  systemd.services.nvidia-fabricmanager.enable = lib.mkForce false;

  nixpkgs.config = {
    cudaSupport = true;
    nvidia.acceptLicense = true;
  };

  # Nomad
  services.nomad = {
    enable = true;
    extraSettingsPlugins = [pkgs.nomad-driver-podman];
    enableDocker = false; # Default is true
    dropPrivileges = false; # Default is true # If true: Error starting agent: client setup failed: failed to initialize client: failed creating alloc mounts dir: mkdir "/var/lib/alloc_mounts": read-only file system
    settings = {
      client.enabled = true;
      server = {
        enabled = true;
        bootstrap_expect = 1;
      };
      plugin = [
        {
          nomad-driver-podman = {
            config = {};
          };
        }
      ];
    };
  };
}

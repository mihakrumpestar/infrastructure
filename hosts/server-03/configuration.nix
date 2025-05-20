{
  lib,
  config,
  ...
}: let
  package_ver = config.boot.kernelPackages.nvidiaPackages.mkDriver rec {
    version = "570.133.20";
    url = "https://us.download.nvidia.com/tesla/${version}/NVIDIA-Linux-x86_64-${version}.run";
    sha256_64bit = "sha256-ElPRexUo6KJL8fNKisZZHJJLmK16MjRL3iU6piKsFgU=";
    persistencedSha256 = "sha256-hdszsACWNqkCh8G4VBNitDT85gk9gJe1BlQ8LdrYIkg=";
    fabricmanagerSha256 = "sha256-7Ti9LxzlVfCOuMumw93uLMe0AcXNsjuyrhoSxcovZco=";
    useSettings = false;
    usePersistenced = true;
    useFabricmanager = true;
  };
in {
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

  # Nvidia Tesla GPU support
  hardware = {
    graphics.enable = true;
    nvidia.datacenter.enable = true;
    nvidia.package = package_ver; # config.boot.kernelPackages.nvidiaPackages.dc_535;

    nvidia-container-toolkit.enable = true;
  };
  systemd.services.nvidia-fabricmanager.enable = lib.mkForce false;

  nixpkgs.config = {
    cudaSupport = true;
    nvidia.acceptLicense = true;
  };

  # https://olai.dev/blog/nvidia-vm-passthrough/

  boot = {
    kernelParams =
      #let
      #  devices = [
      #    "10de:1b38" # NVIDIA Tesla P40
      #    "10de:1288" # NVIDIA GeForce GT 720 VGA
      #    "10de:0e0f" # NVIDIA GeForce GT 720 Audio
      #  ];
      #in
      [
        #"vfio-pci.ids=${lib.concatStringsSep "," devices}"

        "pcie_acs_override=downstream,multifunction" # IOMMU patch
      ];

    initrd.kernelModules = [
      "vfio"
      "vfio_pci"
      #"vfio_virqfd" # No longer in kernel
      "vfio_iommu_type1"
    ];

    # Blacklist the nvidia drivers to make sure they don't get loaded
    #extraModprobeConfig = ''
    #  softdep nvidia pre: vfio-pci
    #  softdep drm pre: vfio-pci
    #  softdep nouveau pre: vfio-pci
    #'';
    #blacklistedKernelModules = [
    #  "nouveau"
    #  "nvidia"
    #  "nvidia_drm"
    #  "nvidia_modeset"
    #  "i2c_nvidia_gpu"
    #];

    ## IOMMU patch

    # Check if it is applied: dmesg | grep acs

    kernelPatches = [
      {
        # pci acs hack, not really safe or a good idea
        name = "acs-overrides";
        patch = ./add-acs-override.patch; # From https://github.com/some-natalie/fedora-acs-override
        # Possible alternative is: https://github.com/cidkidnix/nixcfg/blob/342d0ce35ed2e139e55f7fb1cee7bca2dd5337f9/machines/nixos-desktop/base.nix#L177
        # and: https://github.com/Frogging-Family/linux-tkg/blob/master/linux-tkg-patches/6.14/0006-add-acs-overrides_iommu.patch
        #
        # pkgs.fetchpatch
        #  url = "https://aur.archlinux.org/cgit/aur.git/tree/1001-6.14.0-add-acs-overrides.patch?h=linux-vfio" # This one did not work
        #  sha256 = "sha256-1a6K0jTwZKW50kPh/e7CxbWBEe/Zg9loCc/JGWC/AY4=";
        #};
      }
    ];
  };
}

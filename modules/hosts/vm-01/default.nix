{ den, inputs, ... }:
let
  data = (import "${inputs.infrastructure-secrets}/secrets/data.nix").root;
in
{
  den.aspects.vm-01 = {
    includes = [
      den.aspects.server
      den.aspects.vm-guest
      den.aspects.nomad
    ];
    nixos =
      { config, lib, ... }:
      {
        /*
          Hardware:
            Local KVM VM on pve-01, virtio disk /dev/vda, one ext4 root, no TPM
            14 vCPU, 24 GiB RAM, 1 TiB on Ceph `main`
            NVIDIA GeForce RTX 2080 Ti passed through by the hypervisor
        */

        imports = [ ./_hardware-configuration.nix ];

        my = {
          disks = {
            platform = "guest";
            bootDisk = "/dev/vda";
          };

          # btrfs subvolume wiping has nothing to act on; ext4 is persistent as is.
          impermanence.enable = false;

          nomad.enable = true;
        };

        # Replace the DHCP uplink that den.aspects.server configures
        systemd.network.networks."40-wan" = {
          address = [ data.vm-01.address ];
          gateway = [ data.vm-01.gateway ];
          dns = [
            "1.1.1.1"
            "1.0.0.1"
          ];
          networkConfig.DHCP = lib.mkForce "no";
        };

        # RTX 2080 Ti
        hardware.graphics.enable = true;
        hardware.nvidia = {
          modesetting.enable = true;
          open = false;
          nvidiaSettings = false;
          package = config.boot.kernelPackages.nvidiaPackages.stable;
        };
        services.xserver.videoDrivers = [ "nvidia" ];
        nixpkgs.config.nvidia.acceptLicense = true;
      };
  };
}

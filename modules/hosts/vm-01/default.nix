{ den, ... }:
{
  den.aspects.vm-01 = {
    includes = [
      den.aspects.server
      den.aspects.vm-guest
    ];
    nixos =
      { ... }:
      {
        /*
          Hardware:
            Local KVM VM virtio disk /dev/vda, one ext4 root, no TPM
        */

        imports = [ ./_hardware-configuration.nix ];

        my = {
          disks = {
            platform = "guest";
            bootDisk = "/dev/vda";
          };

          # btrfs subvolume wiping has nothing to act on; ext4 is persistent as is.
          impermanence.enable = false;
        };
      };
  };
}

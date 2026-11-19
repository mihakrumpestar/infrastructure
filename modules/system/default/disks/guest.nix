{ ... }:
{
  den.aspects.disks-guest = {
    nixos =
      {
        config,
        lib,
        ...
      }:
      with lib;
      let
        disks = config.my.disks;
      in
      {
        config = mkIf (disks.platform == "guest") {
          # A guest has no TPM2 or FIDO2 token, so LUKS is impossible; it boots
          # BIOS-style, so it has no ESP and no EFI variables to touch; and an
          # ext4 root has no subvolumes to wipe.
          assertions = [
            {
              assertion = disks.bootLoader == "grub";
              message = "my.disks.platform = \"guest\" boots with GRUB on BIOS (no ESP, no EFI variables) and cannot use another boot loader.";
            }
            {
              assertion = disks.encryptRoot == false;
              message = "my.disks.platform = \"guest\" has no TPM2 or FIDO2 token to unlock LUKS; set my.disks.encryptRoot = false.";
            }
            {
              assertion = !config.my.impermanence.enable;
              message = "my.disks.platform = \"guest\" has an ext4 root with no btrfs subvolumes to wipe; set my.impermanence.enable = false.";
            }
            {
              assertion = disks.swapSize == null;
              message = "my.disks.platform = \"guest\" has no swap: guests are sized for their workload, and a swapfile on virtual disk storage is slower than the OOM kill it prevents. Leave my.disks.swapSize unset.";
            }
          ];
          disko.devices = {
            disk = {
              system = {
                type = "disk";
                device = disks.bootDisk;
                content = {
                  type = "gpt";
                  partitions = {
                    # Disko writes boot.loader.grub.devices from this partition.
                    boot = {
                      size = "1M";
                      type = "EF02";
                      priority = 1;
                    };
                    root = {
                      size = "100%";
                      content = {
                        type = "filesystem";
                        format = "ext4";
                        mountpoint = "/";
                        mountOptions = [
                          "defaults"
                          "noatime"
                          "errors=remount-ro" # A corrupt fs goes read-only instead of carrying on
                        ];
                      };
                    };
                  };
                };
              };
            };
          };
        };
      };
  };
}

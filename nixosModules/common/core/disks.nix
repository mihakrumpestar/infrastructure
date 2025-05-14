{
  config,
  lib,
  ...
}:
with lib; {
  options.my = {
    disks = {
      bootDisk = mkOption {
        type = types.str;
        description = "The device path of the boot disk";
      };
      swapSize = mkOption {
        type = types.str;
        description = "The swap size (e.g., 8G)";
      };
      encryptRoot = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to encrypt the root partition";
      };
    };
  };

  config = {
    disko.devices = {
      disk = {
        system = {
          type = "disk";
          device = config.my.disks.bootDisk;
          content = {
            type = "gpt";
            partitions = {
              ESP = {
                size = "512M";
                type = "EF00"; # EFI System Partition
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                };
              };
              root = let
                # /dev/disk/by-partlabel/disk-system-root
                disk_content = {
                  type = "btrfs";
                  extraArgs = ["-f"];
                  subvolumes = {
                    "/root" = {
                      mountpoint = "/";
                      mountOptions = ["compress=zstd" "noatime"];
                    };
                    "/home" = {
                      mountpoint = "/home";
                      mountOptions = ["compress=zstd" "noatime"];
                    };
                    "/nix" = {
                      mountpoint = "/nix";
                      mountOptions = ["compress=zstd" "noatime"];
                    };
                    "/swap" = {
                      mountpoint = "/.swapvol";
                      swap.swapfile.size = config.my.disks.swapSize; # Same size as memory
                    };
                  };
                };
              in
                if config.my.disks.encryptRoot
                then {
                  size = "100%";
                  content = {
                    type = "luks";
                    name = "crypted";
                    settings = {
                      allowDiscards = true;
                      crypttabExtraOpts = ["fido2-device=auto" "token-timeout=10"]; # cryptenroll
                    };
                    content = disk_content;
                  };
                }
                else {
                  size = "100%";
                  content = disk_content;
                };
            };
          };
        };
      };
    };

    boot.initrd = mkIf config.my.disks.encryptRoot {
      systemd = {
        enable = true;
        fido2.enable = true;
      };
      luks.fido2Support = false; # this is for the old implementation without systemd, don't use it
    };

    # Docs: https://nixos.org/manual/nixos/stable/#sec-luks-file-systems-fido2-systemd

    # systemd-cryptenroll --fido2-device=list
    # Check current keys: sudo systemd-cryptenroll /dev/nvme0n1p2
    # Set FIDO2 key: systemd-cryptenroll --fido2-device=auto --fido2-with-client-pin=no --fido2-with-user-presence=yes /dev/vda2 # --wipe-slot=0
    # List slots: sudo cryptsetup luksDump /dev/nvme0n1p2
    # Remove key: sudo cryptsetup luksRemoveKey /dev/vda2 # Here you enter the password that will be deleted

    # sudo systemd-cryptenroll --unlock-fido2-device=/dev/hidraw1 --fido2-device=/dev/hidraw1 --fido2-with-client-pin=no --fido2-with-user-presence=yes --wipe-slot=all /dev/nvme0n1p2

    # okt 19 11:56:50 systemd-cryptsetup[201]: Timed out waiting for security device, aborting security device based authentication attempt.
    # okt 19 11:56:39 systemd-cryptsetup[201]: Security token not present for unlocking volume disk-system-luks (crypted), please plug it in.

    # Enable swap
    swapDevices = [
      {
        device = "/.swapvol/swapfile";
      }
    ];

    # Optional: Enable hibernation TODO: seems like it does not work as it can't wake form it
    # boot.resumeDevice = "/dev/mapper/crypted";
  };
}

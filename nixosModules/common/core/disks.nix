{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  options.my = {
    disks = {
      bootLoader = mkOption {
        type = types.enum ["systemd-boot" "grub" "lanzaboote"];
        default = "systemd-boot";
        description = "Which boot loader to use: grub for VMs, systemd-boot default, lanzaboote for Secure Boot";
      };
      bootDisk = mkOption {
        type = types.str;
        description = "The device path of the boot disk";
      };
      swapSize = mkOption {
        type = types.str;
        description = "The swap size (e.g., 8G)";
      };
      encryptRoot = mkOption {
        type = types.enum [false "tpm2" "fido2"];
        default = false;
        description = "Whether to encrypt the root partition";
      };
    };
  };

  config = let
    lanzabooteEnabled = config.my.disks.bootLoader == "lanzaboote";
  in {
    disko.devices = {
      disk = {
        system = {
          type = "disk";
          device = config.my.disks.bootDisk;
          content = {
            type = "gpt";
            partitions = {
              boot = mkIf (config.my.disks.bootLoader == "grub") {
                size = "1M";
                type = "EF02";
                priority = 1;
              };
              ESP = {
                size = "2G";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                };
              };
              root = let
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
                      swap = {
                        swapfile.size = config.my.disks.swapSize;
                      };
                    };
                  };
                };
              in
                if (config.my.disks.encryptRoot != false)
                then {
                  size = "100%";
                  content = {
                    type = "luks";
                    name = "crypted";
                    # This means it will give user an interactive password prompt,
                    # be carefull to not have trailing newline in file as unlocking will fail
                    passwordFile = "/tmp/disko-encryption-password.txt";
                    settings = {
                      allowDiscards = true;
                      crypttabExtraOpts =
                        if config.my.disks.encryptRoot == "fido2"
                        then ["fido2-device=auto" "token-timeout=10"]
                        # Docs: https://nixos.org/manual/nixos/stable/#sec-luks-file-systems-fido2-systemd
                        #
                        # systemd-cryptenroll --fido2-device=list
                        # Check current keys: systemd-cryptenroll /dev/nvme0n1p2
                        # Set FIDO2 key: systemd-cryptenroll --fido2-device=auto --fido2-with-client-pin=no --fido2-with-user-presence=yes /dev/vda2 # --wipe-slot=0 or --wipe-slot=all
                        # List slots: cryptsetup luksDump /dev/nvme0n1p2
                        # Remove key: cryptsetup luksRemoveKey /dev/vda2 # Here you enter the password that will be deleted
                        #
                        # systemd-cryptenroll --unlock-fido2-device=/dev/hidraw1 --fido2-device=/dev/hidraw1 --fido2-with-client-pin=no --fido2-with-user-presence=yes --wipe-slot=all /dev/nvme0n1p2
                        else if config.my.disks.encryptRoot == "tpm2"
                        then ["tpm2-device=auto" "tpm2-measure-pcr=yes"]
                        # PCR-15 does not unlock volume, TODO: check if other systems have same problem
                        # systemd-cryptenroll --tpm2-device=list
                        # systemd-cryptenroll --tpm2-device=auto --tpm2-with-pin=no --wipe-slot=all /dev/vda2
                        # Test: systemd-cryptsetup attach <mapping_name> /dev/nvme0n1p2 none tpm2-device=auto
                        else [];
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

    environment.systemPackages = mkIf lanzabooteEnabled [
      pkgs.sbctl
    ];

    boot = {
      loader = {
        systemd-boot.enable = config.my.disks.bootLoader == "systemd-boot";
        grub.enable = config.my.disks.bootLoader == "grub";
        efi.canTouchEfiVariables = !lanzabooteEnabled;
      };

      lanzaboote = mkIf lanzabooteEnabled {
        enable = true;
        pkiBundle = "/var/lib/sbctl";
        autoGenerateKeys.enable = true;
        autoEnrollKeys = {
          enable = true;
          includeMicrosoftKeys = false;
          allowBrickingMyMachine = true;
          autoReboot = true;
        };
      };

      initrd.systemd = mkIf (config.my.disks.encryptRoot != false) {
        enable = true;
        fido2.enable = config.my.disks.encryptRoot == "fido2";
        tpm2.enable = config.my.disks.encryptRoot == "tpm2";
      };
    };

    system.activationScripts.lanzaboote-efi-entry = let
      inherit (pkgs) gawk coreutils gnugrep efibootmgr;
    in
      mkIf lanzabooteEnabled (stringAfter ["etc"] ''
        # Get the device mounted at /boot from /proc/mounts
        BOOT_DEV=$(${gawk}/bin/awk '$2 == "/boot" {print $1}' /proc/mounts | ${coreutils}/bin/head -1)
        if [ -n "$BOOT_DEV" ]; then
          # Get parent device (disk) and partition number
          PART_DEV=$(${coreutils}/bin/basename "$BOOT_DEV")
          DISK="/dev/$(${coreutils}/bin/basename "$(${coreutils}/bin/readlink -f "/sys/class/block/$PART_DEV/..")")"
          PART_NUM=$(${coreutils}/bin/cat "/sys/class/block/$PART_DEV/partition")

          ENTRY_NAME="NixOS"
          ESP_PATH="\EFI\BOOT\BOOTX64.EFI"

          CURRENT_ENTRIES=$(${efibootmgr}/bin/efibootmgr 2>/dev/null)
          ENTRY_NUM=$(echo "$CURRENT_ENTRIES" | ${gnugrep}/bin/grep -oP "Boot\K[0-9A-F]+(?=\*.*$ENTRY_NAME)" | ${coreutils}/bin/head -1)

          if [ -n "$ENTRY_NUM" ]; then
            echo "EFI boot entry '$ENTRY_NAME' already exists as Boot$ENTRY_NUM"

            # Check if it's first in boot order
            BOOT_ORDER=$(echo "$CURRENT_ENTRIES" | ${gnugrep}/bin/grep -oP "BootOrder: \K.*")
            FIRST_ENTRY=$(echo "$BOOT_ORDER" | ${coreutils}/bin/cut -d',' -f1)

            if [ "$FIRST_ENTRY" != "$ENTRY_NUM" ]; then
              # Move it to first position
              NEW_ORDER="$ENTRY_NUM"
              for ENTRY in $(echo "$BOOT_ORDER" | ${coreutils}/bin/tr ',' ' '); do
                if [ "$ENTRY" != "$ENTRY_NUM" ]; then
                  NEW_ORDER="$NEW_ORDER,$ENTRY"
                fi
              done

              echo "Setting boot order: $NEW_ORDER"
              ${efibootmgr}/bin/efibootmgr -o "$NEW_ORDER"
            else
              echo "Boot entry is already first in boot order"
            fi
          else
            echo "Creating EFI boot entry on $DISK partition $PART_NUM"
            ${efibootmgr}/bin/efibootmgr -c -d "$DISK" -p "$PART_NUM" -L "$ENTRY_NAME" -l "$ESP_PATH"
          fi
        fi
      '');
  };
}

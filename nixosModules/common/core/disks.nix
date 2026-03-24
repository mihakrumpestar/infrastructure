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
    tpm2Pcrs = "7+14";
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
                  mountOptions = ["fmask=0077" "dmask=0077"]; # Prevents warning: Random seed file '/boot/loader/random-seed' is world accessible, which is a security hole!
                };
              };
              root = let
                disk_content = {
                  type = "btrfs";
                  extraArgs = ["-f"];
                  subvolumes =
                    {
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
                    }
                    // optionalAttrs config.my.impermanence.enable {
                      "/persistent-root" = {
                        mountpoint = "/persistent-root";
                        mountOptions = ["compress=zstd" "noatime"];
                      };
                      "/persistent-home" = {
                        mountpoint = "/persistent-home";
                        mountOptions = ["compress=zstd" "noatime"];
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

      # Before attempting lanzaboote, your device has to have Secure Boot in Setup Mode

      # sbctl status
      # sbctl verify
      # bootctl status
      lanzaboote = mkIf lanzabooteEnabled {
        enable = true;
        pkiBundle = "/var/lib/sbctl";
        autoGenerateKeys.enable = true;

        # If you don't auto-enroll, run (note that on some devices you will have to enable Secure Boot back manually):
        # sbctl create-keys
        # sbctl enroll-keys
        # reboot
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
        services."systemd-cryptsetup@crypted" = {
          overrideStrategy = "asDropin";
          serviceConfig.TimeoutStartSec = "12s";
        };
      };
    };

    # Lanzaboote does not automatically set the new EFi boot entry as first in UEFI, this code does it for us
    system.activationScripts.lanzaboote-efi-entry = let
      inherit (pkgs) gawk coreutils gnugrep efibootmgr;
    in
      mkIf lanzabooteEnabled (stringAfter ["etc"] ''
        # Only run during nixos-install
        if [ -z "''${NIXOS_INSTALL_BOOTLOADER:-}" ]; then
          true
        else
          BOOT_DEV=$(${gawk}/bin/awk '$2 == "/boot" {print $1}' /proc/mounts | ${coreutils}/bin/head -1)
          if [ -n "$BOOT_DEV" ]; then
            PART_DEV=$(${coreutils}/bin/basename "$BOOT_DEV")
            DISK="/dev/$(${coreutils}/bin/basename $(${coreutils}/bin/readlink -f "/sys/class/block/$PART_DEV/.."))"
            PART_NUM=$(${coreutils}/bin/cat "/sys/class/block/$PART_DEV/partition")

            # Remove existing NixOS entries
            ENTRIES=$(${efibootmgr}/bin/efibootmgr 2>/dev/null | ${gnugrep}/bin/grep -oP 'Boot\K[0-9A-F]+(?=\*.*NixOS)')
            for entry in $ENTRIES; do
              ${efibootmgr}/bin/efibootmgr -b "$entry" -B 2>/dev/null || true
            done

            # Create new entry
            echo "Creating EFI boot entry on $DISK partition $PART_NUM"
            ${efibootmgr}/bin/efibootmgr -c -d "$DISK" -p "$PART_NUM" -L "NixOS" -l '\EFI\BOOT\BOOTX64.EFI'
          fi
        fi
      '');

    systemd.services.tpm2-cryptenroll = mkIf (lanzabooteEnabled && config.my.disks.encryptRoot == "tpm2") {
      description = "Enroll TPM2 with PCR 7 for LUKS decryption after Secure Boot is fully active";
      wantedBy = ["multi-user.target"];
      after = ["boot.mount"];
      requires = ["boot.mount"];

      unitConfig.ConditionPathExists = "!/var/lib/tpm2-cryptenroll-done";

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      path = [pkgs.cryptsetup pkgs.systemd pkgs.coreutils pkgs.mokutil];

      script = ''
        LUKS_DEVICE="${config.boot.initrd.luks.devices.crypted.device}"

        # Check Secure Boot is enabled
        SECURE_BOOT_STATE=$(${pkgs.mokutil}/bin/mokutil --sb-state 2>/dev/null | ${pkgs.coreutils}/bin/head -1)
        if [ "$SECURE_BOOT_STATE" != "SecureBoot enabled" ]; then
          echo "Secure Boot not enabled (state: $SECURE_BOOT_STATE), skipping TPM2 enrollment"
          exit 0
        fi

        echo "Enrolling TPM2 with PCRs ${tpm2Pcrs} for $LUKS_DEVICE"

        if systemd-cryptenroll \
          --tpm2-pcrs=${tpm2Pcrs} \
          --unlock-tpm2-device=auto \
          --tpm2-device=auto \
          --tpm2-with-pin=no \
          --wipe-slot=all \
          "$LUKS_DEVICE"; then
          touch /var/lib/tpm2-cryptenroll-done
          echo "TPM2 enrollment complete, rebooting..."
          systemctl reboot
        else
          echo "TPM2 enrollment failed"
          exit 1
        fi
      '';
    };
  };
}

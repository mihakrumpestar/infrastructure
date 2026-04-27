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
        default = "lanzaboote";
        description = "Which boot loader to use: grub for VMs, systemd-boot, lanzaboote (default) for Secure Boot";
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
      pcrlockSupport = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether the machine supports systemd-pcrlock (only applicable to TPM2).
          You have to disable it on machines that do not support it.
          Test: /run/current-system/systemd/lib/systemd/systemd-pcrlock is-supported
        '';
      };
    };
  };

  config = let
    lanzabooteEnabled = config.my.disks.bootLoader == "lanzaboote";
    fido2Enabled = config.my.disks.encryptRoot == "fido2";
    tpm2Enabled = config.my.disks.encryptRoot == "tpm2";
    tpm2PcrlockEnabled = tpm2Enabled && config.my.disks.pcrlockSupport;

    pcr15 = "15:sha256=0000000000000000000000000000000000000000000000000000000000000000";
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
                  mountOptions = ["fmask=0077" "dmask=0077"]; # Solves warning: Random seed file '/boot/loader/random-seed' is world accessible, which is a security hole!
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
                    # passwordFile will give user an interactive password prompt if file will not be provided,
                    # be carefull to not have trailing newline in file as unlocking will fail in that case
                    passwordFile = "/tmp/disko-encryption-password.txt";
                    settings = {
                      allowDiscards = true;
                      crypttabExtraOpts =
                        #
                        # FIDO2
                        #
                        if fido2Enabled
                        then ["fido2-device=auto" "token-timeout=10"]
                        # Docs: https://nixos.org/manual/nixos/stable/#sec-luks-file-systems-fido2-systemd
                        #
                        # systemd-cryptenroll --fido2-device=list
                        # Check current keys: systemd-cryptenroll /dev/nvme0n1p2
                        # Set FIDO2 key: systemd-cryptenroll --fido2-device=auto --fido2-with-client-pin=no --fido2-with-user-presence=yes /dev/vda2 # --wipe-slot=0 or --wipe-slot=all
                        # List slots: cryptsetup luksDump /dev/nvme0n1p2
                        # Remove key: cryptsetup luksRemoveKey /dev/vda2 # Here you enter the password that will be deleted
                        #
                        # Rekey with another key: systemd-cryptenroll --unlock-fido2-device=/dev/hidraw1 --fido2-device=/dev/hidraw2 --fido2-with-client-pin=no --fido2-with-user-presence=yes --wipe-slot=all /dev/nvme0n1p2
                        #
                        # TPM2
                        #
                        else if tpm2Enabled
                        then ["tpm2-device=auto" "tpm2-measure-pcr=yes"] # tpm2-measure-pcr is required for PCR15
                        # Note: look below in Lanzaboote setup
                        #
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
        efi.canTouchEfiVariables = true; # Allow changing boot order and boot entrys
      };

      # IMPORTANT: Before attempting Lanzaboote, your device has to have Secure Boot in Setup Mode
      # Docs: https://nix-community.github.io/lanzaboote/
      # Not all options are in docs, for all look into: https://github.com/nix-community/lanzaboote/blob/master/nix/modules/lanzaboote.nix

      # sbctl status
      # sbctl verify
      # bootctl status
      lanzaboote = mkIf lanzabooteEnabled {
        enable = true;
        pkiBundle = "/var/lib/sbctl";
        autoGenerateKeys.enable = true;

        # If you don't auto-enroll, run:
        # sbctl create-keys
        # sbctl enroll-keys
        # reboot
        # (note that on some devices you will have to enable Secure Boot back manually)
        autoEnrollKeys = {
          enable = true;
          includeMicrosoftKeys = false;
          allowBrickingMyMachine = true;
          autoReboot = true;
        };

        # Only available on machines that return "yes" for command:
        # /run/current-system/systemd/lib/systemd/systemd-pcrlock is-supported
        measuredBoot = mkIf tpm2PcrlockEnabled {
          enable = true;
          pcrs = [4 7];
          # https://uapi-group.org/specifications/specs/linux_tpm_pcr_registry/
          # No. 4 is Lanzaboote itself with full boot chain
          # No. 7 is Secure boot state.
          # We don't have no. 0, since it would break setup on BIOS updates
          autoCryptenroll = {
            enable = true; # Will wipe out any other tpm2 key
            inherit (config.boot.initrd.luks.devices.crypted) device;
            autoReboot = true;
          };
        };
      };

      initrd.systemd = mkIf (config.my.disks.encryptRoot != false) {
        enable = true;
        fido2.enable = fido2Enabled;
        tpm2.enable = tpm2Enabled;

        # Sometimes on reboots the FIDO2 key is not detected immediately,
        # so we reset the crypted service, instead of resetting (repluging) the FIDO2 key
        services."systemd-cryptsetup@crypted" = {
          overrideStrategy = "asDropin";
          serviceConfig.TimeoutStartSec = "12s";
        };
      };
    };

    systemd.services.auto-cryptenroll = mkIf tpm2PcrlockEnabled {
      serviceConfig.ExecStart = let
        cfg = config.boot.lanzaboote.measuredBoot;
      in
        lib.mkForce [
          config.boot.loader.external.installHook
          ''
            systemd-cryptenroll \
              --wipe-slot=tpm2 \
              --tpm2-device=auto \
              --unlock-tpm2-device=auto \
              --tpm2-pcrlock=${cfg.pcrlockPolicy} \
              --tpm2-pcrs=${pcr15} \
              ${cfg.autoCryptenroll.device}
          ''
        ];
    };

    # Static PCR enrollment (when pcrlock not available)
    systemd.services.tpm2-cryptenroll = mkIf (lanzabooteEnabled && tpm2Enabled && !config.my.disks.pcrlockSupport) {
      description = "Enroll TPM2 with PCR 7+14 for LUKS decryption";
      wantedBy = ["multi-user.target"];
      after = ["boot.mount"];
      requires = ["boot.mount"];
      unitConfig = {
        ConditionPathExists = "!/var/lib/tpm2-cryptenroll/done";
        ConditionSecurity = "uefi-secureboot";
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StateDirectory = "tpm2-cryptenroll";
      };
      path = [pkgs.cryptsetup pkgs.systemd pkgs.coreutils];
      script = ''
        systemd-cryptenroll \
          --tpm2-device=auto \
          --tpm2-pcrs=7+14+${pcr15} \
          --wipe-slot=all \
          ${config.boot.initrd.luks.devices.crypted.device}
        touch /var/lib/tpm2-cryptenroll/done
      '';
    };
  };
}

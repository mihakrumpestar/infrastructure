{ den, ... }:
{
  den.aspects.disks = {
    # One implementation per machine class, selected by my.disks.platform.
    # Both are always imported; each guards itself on the option.
    #
    # Not to be confused with den.aspects.vm-guest, which is about the qemu
    # agent and the TPM-less sops identity, not about how storage is laid out.
    includes = [
      den.aspects.disks-guest
      den.aspects.disks-physical
    ];

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
        options.my.disks = {
          # Set on every host; there is no sensible default. Kept here rather
          # than in disks/ because both platforms branch on it.
          platform = mkOption {
            type = types.enum [
              "guest"
              "physical"
            ];
            default = "physical";
            description = ''
              Machine class, which picks the storage implementation in
              modules/system/default/disks/: "physical" is a bare-metal machine
              with an ESP, Secure Boot and a TPM2 or FIDO2 token to unlock the
              root; "guest" is a virtual machine with BIOS + GRUB, no ESP and no
              LUKS. The default only exists so the option is total; set it.
            '';
          };

          bootLoader = mkOption {
            type = types.enum [
              "systemd-boot"
              "grub"
              "lanzaboote"
            ];
            default = if config.my.disks.platform == "guest" then "grub" else "lanzaboote";
            defaultText = lib.literalExpression ''"grub" for platform = "guest", "lanzaboote" otherwise'';
            description = "Which boot loader to use: GRUB for guests on BIOS, Lanzaboote for physical machines on Secure Boot.";
          };

          bootDisk = mkOption {
            type = types.str;
            description = "The device path of the boot disk";
          };

          swapSize = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              Swapfile size (e.g. "4G") for the physical (btrfs) layout, where
              it becomes the /swap subvolume. zram sits in front of it, so this
              is an overflow tier, not the primary swap. The guest layout has
              no swap: those hosts are sized for their workload, and a swapfile
              on virtual disk storage is slower than the OOM kill it prevents.
              null disables it.
            '';
          };

          encryptRoot = mkOption {
            type = types.enum [
              false
              "tpm2"
              "fido2"
            ];
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

        config = {
          # Everything below follows from the layout each platform puts on
          # disk; the per-layout constraints live with their layout in
          # disks/guest.nix and disks/physical.nix.
          boot.initrd.systemd = {
            # Token support in the initrd follows encryptRoot, not the
            # platform. Both options default to the initrd systemd package,
            # which is built with FIDO2 and TPM2 compiled in, so leaving them
            # unset for a guest pulls both into an unencrypted initrd.
            fido2.enable = disks.encryptRoot == "fido2";
            tpm2.enable = disks.encryptRoot == "tpm2";
          };

          # Mechanical from my.disks.bootLoader, identical on both platforms:
          # whichever loader is selected is the only one enabled, and the
          # layout builder puts the matching EF02 or ESP partition on disk.
          boot.loader = {
            systemd-boot.enable = disks.bootLoader == "systemd-boot";
            grub.enable = disks.bootLoader == "grub";
            efi.canTouchEfiVariables = true; # Allow changing boot order and boot entrys
          };
        };
      };
  };
}

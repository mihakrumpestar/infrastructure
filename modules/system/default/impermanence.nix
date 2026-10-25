{ ... }:
{
  den.aspects.impermanence = {
    nixos =
      {
        config,
        lib,
        pkgs,
        utils,
        ...
      }:
      with lib;
      {
        options.my.impermanence = {
          enable = mkEnableOption "impermanence with btrfs subvolume wiping" // {
            default = true;
          };

          fullyImpermanent = mkOption {
            type = types.bool;
            default = false;
            description = "Enable fully impermanent mode - only persist bare minimum (machine-id and SSH host keys)";
          };

          retentionDays = mkOption {
            type = types.ints.positive;
            default = 30;
            description = "Delete impermanence snapshots older than this many days.";
          };

          files = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "Additional files to persist (beyond defaults)";
            example = [ "/etc/custom-file" ];
          };

          directories = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "Additional directories to persist (beyond defaults)";
            example = [ "/var/lib/myapp" ];
          };

          userFiles = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "Additional user files to persist (beyond defaults, applied to all users)";
            example = [ ".custom_file" ];
          };

          userDirectories = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "Additional user directories to persist (beyond defaults, applied to all users)";
            example = [ ".myapp" ];
          };
        };

        config =
          let
            cfg = config.my.impermanence;
            btrfsDevice = config.fileSystems."/".device;
            inherit (pkgs) btrfs-progs;
            systemdInitrd = config.boot.initrd.systemd.enable;
            # Device unit name for the btrfs root device, so the wipe service
            # waits for the device to be available before trying to mount it.
            btrfsDeviceUnit = "${utils.escapeSystemdPath btrfsDevice}.device";

            minimumFiles = [
              "/etc/machine-id"
              "/etc/ssh/ssh_host_ed25519_key"
              "/etc/ssh/ssh_host_ed25519_key.pub"
              "/etc/ssh/ssh_host_rsa_key"
              "/etc/ssh/ssh_host_rsa_key.pub"
            ];

            minimumDirectories = [
              "/var/lib/nixos"
            ];

            defaultFiles = minimumFiles ++ [ "/root/.zsh_history" ];

            defaultDirectories = minimumDirectories ++ [
              "/var/log"
              "/etc/NetworkManager/system-connections"

              # Simplified setup, list of subdirs that really need to persist in "/var/lib":
              # bluetooth, systemd, auto-cryptenroll, sbctl, docker, pcrlock.d, etc.
              "/var/lib"

              # Data for multiple purposes (orchestrator, etc.)
              "/mnt/data"
            ];

            defaultUserFiles = [
              ".zsh_history"
            ];

            defaultUserDirectories = [
              ".cache"
              ".config"
              ".local/share/" # Program data and Steam games are saved here
              ".local/state" # Wireplumber, ...
              ".pki"
              ".vscode-oss-shared" # VSCodium
              ".librewolf"
              ".steam"
              ".ssh" # SSH has issues having just ".ssh/known_hosts" file
              "go" # Golang cache
              "Desktop"
              "Documents"
              "Downloads"
              "Pictures"
              "Videos"
              "Projects"
              "repos" # TODO: remove after migrated all repos to "Projects"
            ];

            filesToPersist =
              if cfg.fullyImpermanent then minimumFiles ++ cfg.files else defaultFiles ++ cfg.files;
            directoriesToPersist =
              if cfg.fullyImpermanent then
                minimumDirectories ++ cfg.directories
              else
                defaultDirectories ++ cfg.directories;
            userFilesToPersist = if cfg.fullyImpermanent then [ ] else defaultUserFiles ++ cfg.userFiles;
            userDirectoriesToPersist =
              if cfg.fullyImpermanent then [ ] else defaultUserDirectories ++ cfg.userDirectories;

            wipeScript = ''
              set -euo pipefail

              readonly btrfsBin="${btrfs-progs}/bin/btrfs"
              readonly snapshotRoot=/btrfs_root

              # The device node may not exist yet when this unit is queued.
              for _ in {1..50}; do
                [[ -e "${btrfsDevice}" ]] && break
                sleep 0.2
              done
              if [[ ! -e "${btrfsDevice}" ]]; then
                echo "impermanence: ${btrfsDevice} did not appear" >&2
                exit 1
              fi

              mkdir -p "$snapshotRoot"
              # Always use the top-level subvolume, regardless of the default subvolume.
              mount -o subvolid=5 "${btrfsDevice}" "$snapshotRoot"
              trap 'umount "$snapshotRoot" 2>/dev/null || true' EXIT

              timestamp=$(date "+%Y-%m-%d_%H:%M:%S")
              mkdir -p "$snapshotRoot/old_roots"
              for subvol in root home; do
                if [[ -e "$snapshotRoot/$subvol" ]]; then
                  mv "$snapshotRoot/$subvol" "$snapshotRoot/old_roots/$subvol-$timestamp"
                fi
              done

              "$btrfsBin" subvolume create "$snapshotRoot/root"
              "$btrfsBin" subvolume create "$snapshotRoot/home"

              cutoff_date=$(date -d "${toString cfg.retentionDays} days ago" +%s)
              deleted=0
              for old_root in "$snapshotRoot"/old_roots/*; do
                [[ -d "$old_root" ]] || continue
                name="''${old_root##*/}"
                [[ "$name" =~ ^[a-z]+-([0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}:[0-9]{2}:[0-9]{2})$ ]] || continue
                # tr avoids parameter-expansion escaping pitfalls inside Nix strings.
                snapshot_date=$(tr '_' ' ' <<< "''${BASH_REMATCH[1]}")
                backup_epoch=$(date -d "$snapshot_date" +%s 2>/dev/null) || continue
                (( backup_epoch < cutoff_date )) || continue
                if "$btrfsBin" subvolume delete -R "$old_root"; then
                  deleted=$((deleted + 1))
                else
                  echo "impermanence: failed to delete $old_root" >&2
                fi
              done
              echo "impermanence: removed $deleted snapshot(s) older than ${toString cfg.retentionDays} days"

              if ! umount "$snapshotRoot"; then
                echo "impermanence: failed to unmount $snapshotRoot" >&2
              fi
            '';
          in
          mkIf cfg.enable {
            fileSystems."/persistent-root".neededForBoot = true;
            fileSystems."/persistent-home".neededForBoot = true;
            fileSystems."/home".neededForBoot = true;

            boot.initrd = {
              supportedFilesystems = [ "btrfs" ];
              postResumeCommands = mkIf (!systemdInitrd) (mkAfter wipeScript);
              systemd = mkIf systemdInitrd {
                services.impermanence-wipe = {
                  description = "Wipe root and home btrfs subvolumes for impermanence";
                  wantedBy = [ "initrd.target" ];
                  after = [
                    "cryptsetup.target"
                    btrfsDeviceUnit # btrfsDeviceUnit is required to make sure block device was available before service starts
                  ];
                  requires = [ btrfsDeviceUnit ];
                  before = [ "sysroot.mount" ];
                  unitConfig.DefaultDependencies = false;
                  serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = true;
                  };
                  script = wipeScript;
                };
              };
            };

            environment.persistence."/persistent-root" = {
              hideMounts = true;
              allowTrash = true;
              files = filesToPersist;
              directories = directoriesToPersist;
            };

            # Apperently more performant than home.persistence: https://github.com/nix-community/impermanence/issues/206#issuecomment-2978804033
            environment.persistence."/persistent-home" = {
              hideMounts = true;
              allowTrash = true;
              users =
                lib.genAttrs (builtins.attrNames (lib.filterAttrs (_: u: u.isNormalUser) config.users.users))
                  (_: {
                    files = userFilesToPersist;
                    directories = userDirectoriesToPersist;
                  });
            };
          };
      };
  };
}

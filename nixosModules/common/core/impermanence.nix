{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  options.my.impermanence = {
    enable = mkEnableOption "impermanence with btrfs subvolume wiping" // {default = false;};

    fullyImpermanent = mkOption {
      type = types.bool;
      default = false;
      description = "Enable fully impermanent mode - only persist bare minimum (machine-id and SSH host keys)";
    };

    files = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional files to persist (beyond defaults)";
      example = ["/etc/custom-file"];
    };

    directories = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional directories to persist (beyond defaults)";
      example = ["/var/lib/myapp"];
    };

    userFiles = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional user files to persist (beyond defaults, applied to all users)";
      example = [".custom_file"];
    };

    userDirectories = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional user directories to persist (beyond defaults, applied to all users)";
      example = [".myapp"];
    };
  };

  config = let
    cfg = config.my.impermanence;
    btrfsDevice = config.fileSystems."/".device;
    inherit (pkgs) btrfs-progs;
    systemdInitrd = config.boot.initrd.systemd.enable;

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

    defaultFiles = minimumFiles ++ ["/root/.zsh_history"];

    defaultDirectories =
      minimumDirectories
      ++ [
        "/var/log"
        "/var/lib/bluetooth"
        "/var/lib/systemd/coredump"
        "/etc/NetworkManager/system-connections"
        "/var/lib/sbctl" # Lanzaboote keys
      ];

    defaultUserFiles = [
      ".zsh_history"
      ".ssh/known_hosts"
    ];

    defaultUserDirectories = [
      ".cache"
      ".config"
      ".local/share/" # Program data and Steam games are saved here
      ".pki"
      ".librewolf"
      ".steam"
      "Desktop"
      "Documents"
      "Downloads"
      "Pictures"
      "Videos"
      "repos"
    ];

    filesToPersist =
      if cfg.fullyImpermanent
      then minimumFiles
      else defaultFiles ++ cfg.files;
    directoriesToPersist =
      if cfg.fullyImpermanent
      then minimumDirectories
      else defaultDirectories ++ cfg.directories;
    userFilesToPersist =
      if cfg.fullyImpermanent
      then []
      else defaultUserFiles ++ cfg.userFiles;
    userDirectoriesToPersist =
      if cfg.fullyImpermanent
      then []
      else defaultUserDirectories ++ cfg.userDirectories;

    wipeScript = ''
      set -euo pipefail
      mkdir -p /btrfs_root
      mount ${btrfsDevice} /btrfs_root

      # Move old root and home to old_roots with timestamp
      mkdir -p /btrfs_root/old_roots
      for subvol in root home; do
        if [[ -e /btrfs_root/$subvol ]]; then
          timestamp=$(date "+%Y-%m-%d_%H:%M:%S")
          mv /btrfs_root/$subvol "/btrfs_root/old_roots/$subvol-$timestamp"
        fi
      done

      # Create fresh root and home subvolumes
      ${btrfs-progs}/bin/btrfs subvolume create /btrfs_root/root
      ${btrfs-progs}/bin/btrfs subvolume create /btrfs_root/home

      # Cleanup old roots older than 30 days
      delete_subvolume_recursively() {
        for subvol in $("${btrfs-progs}/bin/btrfs" subvolume list -o "$1" 2>/dev/null | cut -f 9- -d ' '); do
          delete_subvolume_recursively "/btrfs_root/$subvol"
        done
        "${btrfs-progs}/bin/btrfs" subvolume delete "$1" 2>/dev/null || true
      }

      cutoff_date=$(date -d "30 days ago" +%s)
      for old_root in /btrfs_root/old_roots/*; do
        [[ -d "$old_root" ]] || continue
        # Extract timestamp from name (format: subvol-YYYY-MM-DD_HH:MM:SS)
        backup_date=$(echo "$(basename "$old_root")" | sed -n 's/[^0-9-]*-\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}_[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}\)/\1/p')
        [[ -n "$backup_date" ]] || continue
        # Replace underscore with space for date parsing
        backup_epoch=$(date -d "$${backup_date/_/ }" +%s 2>/dev/null) || continue
        if [[ "$backup_epoch" -lt "$cutoff_date" ]]; then
          delete_subvolume_recursively "$old_root"
        fi
      done

      umount /btrfs_root
    '';
  in
    mkIf cfg.enable {
      fileSystems."/persistent-root".neededForBoot = true;
      fileSystems."/persistent-home".neededForBoot = true;
      fileSystems."/home".neededForBoot = true;

      boot.initrd = {
        supportedFilesystems = ["btrfs"];
        postResumeCommands = mkIf (!systemdInitrd) (mkAfter wipeScript);
        systemd = mkIf systemdInitrd {
          services.impermanence-wipe = {
            description = "Wipe root and home btrfs subvolumes for impermanence";
            wantedBy = ["initrd.target"];
            after = ["cryptsetup.target"];
            before = ["sysroot.mount"];
            unitConfig.DefaultDependencies = false;
            serviceConfig.Type = "oneshot";
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

      home-manager.sharedModules = [
        {
          home.persistence."/persistent-home" = {
            enable = true;
            files = userFilesToPersist;
            directories = userDirectoriesToPersist;
          };
        }
      ];
    };
}

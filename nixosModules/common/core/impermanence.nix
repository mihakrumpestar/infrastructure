{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  options.my.impermanence = {
    enable = mkEnableOption "impermanence with btrfs subvolume wiping" // {default = true;};

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

    defaultFiles = [
      "/etc/machine-id"

      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"

      "/root/.zsh_history"
      "/root/.zcompdump"
    ];

    defaultDirectories = [
      "/var/log"
      "/var/lib/bluetooth"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
      "/etc/NetworkManager/system-connections"
      "/var/lib/sbctl"
    ];

    defaultUserFiles = [
      ".zsh_history"
      ".zcompdump"
      ".ssh/known_hosts"
    ];

    defaultUserDirectories = [
      ".cache"
      ".config"
      ".local/share/"
      ".pki"
      ".librewolf"
      "Desktop"
      "Documents"
      "Downloads"
      "Pictures"
      "Videos"
      "repos"
    ];

    wipeScript = ''
      set -euo pipefail
      mkdir -p /btrfs_root
      mount ${btrfsDevice} /btrfs_root

      # Move old root and home to old_roots with timestamp
      mkdir -p /btrfs_root/old_roots
      for subvol in root home; do
        if [[ -e /btrfs_root/$subvol ]]; then
          timestamp=$(date --date="@$(stat -c %Y /btrfs_root/$subvol)" "+%Y-%m-%d_%H:%M:%S")
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

      for old_root in $(find /btrfs_root/old_roots -maxdepth 1 -type d -mtime +30 2>/dev/null); do
        delete_subvolume_recursively "$old_root"
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
        files = defaultFiles ++ cfg.files;
        directories = defaultDirectories ++ cfg.directories;
      };

      home-manager.sharedModules = [
        {
          home.persistence."/persistent-home" = {
            enable = true;
            files = defaultUserFiles ++ cfg.userFiles;
            directories = defaultUserDirectories ++ cfg.userDirectories;
          };
        }
      ];
    };
}

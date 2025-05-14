{
  config,
  lib,
  pkgs,
  ...
}: let
  rcloneBase = {
    # User service for Rclone mounting
    #
    # Place in ~/.config/systemd/user/
    # File must include the '@' (ex rclone@.service)
    # As your normal user, run
    #   systemctl --user daemon-reload
    # You can now start/enable each remote by using rclone@<remote>
    #   systemctl --user enable --now rclone@dropbox

    Unit = {
      Description = "rclone: Remote FUSE filesystem for cloud storage config %i";
      Documentation = "man:rclone(1)";
      After = ["network-online.target"];
      Wants = ["network-online.target"];
    };

    Service = {
      Type = "notify";
      ExecStartPre = [
        "-${pkgs.coreutils}/bin/mkdir -p %h/mnt/%i"
        # Force unmount any leftover mount
        "${pkgs.bash}/bin/bash -c \"if ${pkgs.util-linux}/bin/findmnt -rno TARGET %h/mnt/%i; then /run/wrappers/bin/fusermount -uz %h/mnt/%i; fi\""
      ];
      ExecStart = ''
        ${pkgs.rclone}/bin/rclone mount \
          --config=${config.sops.secrets.rclone_config.path} \
          --dir-cache-time 1m0s \
          --poll-interval 30s \
          --vfs-cache-mode full \
          --vfs-cache-max-size 2G \
          --vfs-cache-poll-interval 30s \
          --log-level INFO \
          --log-file /tmp/rclone-%i.log \
          --umask 022 \
          --allow-other \
          %i: %h/mnt/%i
      ''; # Debug with "-vv \" and remove "--log-level"
      ExecStop = "/run/wrappers/bin/fusermount -u %h/mnt/%i";

      # NixOS patch
      Environment = ["PATH=/run/wrappers/bin/:$PATH"];
    };
  };
in {
  # Mount remote storage
  # home-manager does not have overrideStrategy, so we have to improvise
  systemd.user.services = {
    "rclone@" = rcloneBase;
    "rclone@nextcloud-personal" = lib.recursiveUpdate rcloneBase {
      Install = {
        WantedBy = ["default.target"];
      };
    };
  };

  sops.secrets.rclone_config.path = ".config/rclone/rclone.conf";

  # rclone listremotes

  my.home.mutableFile.".config/Nextcloud/nextcloud.cfg".text = let
    inherit (config.my.store-secrets.secrets.nextcloud) username;
  in ''
    [General]
    clientVersion=3.14.1
    confirmExternalStorage=true
    crashReporter=false
    isVfsEnabled=false
    launchOnSystemStartup=false
    monoIcons=false
    moveToTrash=true
    newBigFolderSizeLimit=500
    notifyExistingFoldersOverLimit=false
    optionalServerNotifications=true
    showCallNotifications=true
    stopSyncingExistingFoldersOverLimit=false
    useNewBigFolderSizeLimit=true

    [Accounts]
    0\Folders\1\ignoreHiddenFiles=false
    0\Folders\1\journalPath=.sync_cae4f91648db.db
    0\Folders\1\localPath=${config.home.homeDirectory}/Documents/
    0\Folders\1\paused=false
    0\Folders\1\targetPath=/private/Documents
    0\Folders\1\version=2
    0\Folders\1\virtualFilesMode=off
    0\Folders\2\ignoreHiddenFiles=false
    0\Folders\2\journalPath=.sync_8d4814a7e73b.db
    0\Folders\2\localPath=${config.home.homeDirectory}/Downloads/
    0\Folders\2\paused=false
    0\Folders\2\targetPath=/private/Downloads
    0\Folders\2\version=2
    0\Folders\2\virtualFilesMode=off
    0\authType=webflow
    0\dav_user=${username}
    0\displayName=${username}
    0\networkDownloadLimit=0
    0\networkDownloadLimitSetting=-2
    0\networkProxyHostName=
    0\networkProxyNeedsAuth=false
    0\networkProxyPort=0
    0\networkProxySetting=0
    0\networkProxyType=2
    0\networkProxyUser=
    0\networkUploadLimit=0
    0\networkUploadLimitSetting=-2
    0\serverColor=@Variant(\0\0\0\x43\x1\xff\xff\0\0\x82\x82\xc9\xc9\0\0)
    0\serverHasValidSubscription=false
    0\serverTextColor=@Variant(\0\0\0\x43\x1\xff\xff\xff\xff\xff\xff\xff\xff\0\0)
    0\serverVersion=29.0.0.19
    0\url=${config.my.store-secrets.secrets.nextcloud.url}
    0\version=1
    0\webflow_user=${username}
    version=2

    [Settings]
    geometry=@ByteArray(\x1\xd9\xd0\xcb\0\x3\0\0\0\0\0\0\0\0\x1\xf3\0\0\x2\xcc\0\0\x3\xf1\0\0\0\0\0\0\x1\xf3\0\0\x2\xcc\0\0\x3\xf1\0\0\0\0\0\0\0\0\n\0\0\0\0\0\0\0\x1\xf3\0\0\x2\xcc\0\0\x3\xf1)
  '';
}

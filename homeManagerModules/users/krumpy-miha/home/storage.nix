{
  config,
  lib,
  pkgs,
  vars,
  ...
}: {
  age.secrets."rclone_config" = {
    file = /${vars.secretsDir}/secrets/users/krumpy-miha/rclone.conf.age;
    path = "${config.xdg.configHome}/rclone/rclone.conf";
  };

  # Mount remote storage
  # home-manager does not have overrideStrategy, so we have to improvise
  systemd.user.services = let
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
            --config=${config.age.secrets."rclone_config".path} \
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

        # Restart settings
        Restart = "on-failure";
        RestartSec = "10s";
        StartLimitBurst = 3;
        StartLimitInterval = "120s";
      };
    };
  in {
    "rclone@" = rcloneBase;
    "rclone@nextcloud-personal" = lib.recursiveUpdate rcloneBase {
      Install = {
        WantedBy = ["default.target"];
      };
    };

    "rclone-bisync-Documents" = {
      Unit = {
        Description = "rclone bisync: Documents sync (inotify + periodic)";
        Documentation = "man:rclone(1) man:inotifywait(1)";
        After = ["network-online.target"];
        Wants = ["network-online.target"];
      };
      Service = {
        Type = "simple";
        ExecStart = let
          script = pkgs.writeShellScript "rclone-bisync-Documents" ''
            SYNC_PATH="$HOME/Documents"
            SYNC_DELAY=60 # 60 sec
            SYNC_INTERVAL=1800 # 30 min
            BISYNC_CACHE="$HOME/.cache/rclone/bisync"
            LISTING1="$BISYNC_CACHE/nextcloud-personal_private_Documents..home_krumpy-miha_Documents.path1.lst"
            LISTING2="$BISYNC_CACHE/nextcloud-personal_private_Documents..home_krumpy-miha_Documents.path2.lst"

            do_sync() {
              RESYNC_FLAG=""
              # First run needs --resync to initialize
              if [ ! -f "$LISTING1" ] || [ ! -f "$LISTING2" ]; then
                RESYNC_FLAG="--resync"
              fi

              ${pkgs.rclone}/bin/rclone bisync nextcloud-personal:private/Documents "$SYNC_PATH" \
                --config=${config.age.secrets."rclone_config".path} \
                --log-file /tmp/rclone-bisync-Documents.log \
                --log-level INFO \
                --conflict-resolve newer \
                --backup-dir1 nextcloud-personal:private/Documents-backup \
                --backup-dir2 "$HOME/.local/share/rclone-bisync-backup/Documents" \
                --create-empty-src-dirs \
                --resilient \
                --recover \
                --max-lock 2m \
                $RESYNC_FLAG
            }

            # Initial sync
            do_sync

            # Watch loop: local changes trigger immediate sync, periodic sync catches remote changes
            while true; do
              ${pkgs.inotify-tools}/bin/inotifywait --recursive \
                --timeout "$SYNC_INTERVAL" \
                -e modify,delete,create,move "$SYNC_PATH" 2>/dev/null
              EXIT_CODE=$?
              if [ $EXIT_CODE -eq 0 ]; then
                # Local change detected - sync after delay to batch changes
                sleep "$SYNC_DELAY"
                do_sync
              elif [ $EXIT_CODE -eq 2 ]; then
                # Timeout - no local changes, sync for remote changes
                do_sync
              fi
            done
          '';
        in "${script}";
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };
  };

  systemd.user.timers."rclone-bisync-Documents" = {
    Unit = {
      Description = "Timer: rclone bisync Documents sync (2 min after login)";
    };
    Timer = {
      OnStartupSec = "2min";
    };
    Install = {
      WantedBy = ["timers.target"];
    };
  };
}

{
  config,
  lib,
  pkgs,
  vars,
  ...
}: let
  rcloneConfigPath = config.age.secrets."rclone_config".path;

  mkBisyncService = {
    name,
    remotePath,
    localPath,
    syncDelay ? 30, # 30 sec
    syncInterval ? 900, # 15 min
    startDelay ? "2min",
  }: {
    service = {
      Unit = {
        Description = "rclone bisync: ${name} sync (inotify + periodic)";
        Documentation = "man:rclone(1) man:inotifywait(1)";
        After = ["network-online.target"];
        Wants = ["network-online.target"];
      };
      Service = {
        Type = "simple";
        ExecStart = let
          script = pkgs.writeShellScript "rclone-bisync-${name}" ''
            SYNC_PATH="$HOME/${localPath}"
            SYNC_DELAY=${toString syncDelay}
            SYNC_INTERVAL=${toString syncInterval}

            mkdir -p "$SYNC_PATH"

            do_sync() {
              RESYNC_FLAG=""
              if [ ! -d "$SYNC_PATH" ] || [ -z "$(ls -A "$SYNC_PATH" 2>/dev/null)" ]; then
                RESYNC_FLAG="--resync"
              fi

              ${pkgs.rclone}/bin/rclone bisync "${remotePath}" "$SYNC_PATH" \
                --config=${rcloneConfigPath} \
                --log-file /tmp/rclone-bisync-${name}.log \
                --log-level INFO \
                --conflict-resolve newer \
                --backup-dir1 "${remotePath}-backup" \
                --backup-dir2 "$HOME/.local/share/rclone-bisync-backup/${name}" \
                --create-empty-src-dirs \
                --resilient \
                --compare "size,modtime,checksum" \
                --max-lock 2m \
                $RESYNC_FLAG
            }

            do_sync

            while true; do
              ${pkgs.inotify-tools}/bin/inotifywait --recursive \
                --timeout "$SYNC_INTERVAL" \
                -e modify,delete,create,move "$SYNC_PATH" 2>/dev/null
              EXIT_CODE=$?
              if [ $EXIT_CODE -eq 0 ]; then
                sleep "$SYNC_DELAY"
                do_sync
              elif [ $EXIT_CODE -eq 2 ]; then
                do_sync
              fi
            done
          '';
        in "${script}";
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };

    timer = {
      Unit.Description = "Timer: rclone bisync ${name} sync (${startDelay} after login)";
      Timer.OnStartupSec = startDelay;
      Install.WantedBy = ["timers.target"];
    };
  };

  bisyncServices = [
    {
      name = "Documents";
      remotePath = "nextcloud-personal:private/Documents";
      localPath = "Documents";
    }
    {
      name = "Sidebery";
      remotePath = "nextcloud-personal:private/Downloads/Sidebery";
      localPath = "Downloads/Sidebery";
      startDelay = "3min";
    }
  ];

  rcloneMountBase = {
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
        "${pkgs.bash}/bin/bash -c \"if ${pkgs.util-linux}/bin/findmnt -rno TARGET %h/mnt/%i; then /run/wrappers/bin/fusermount -uz %h/mnt/%i; fi\""
      ];
      ExecStart = ''
        ${pkgs.rclone}/bin/rclone mount \
          --config=${rcloneConfigPath} \
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
      '';
      ExecStop = "/run/wrappers/bin/fusermount -u %h/mnt/%i";
      Environment = ["PATH=/run/wrappers/bin/:$PATH"];
      Restart = "on-failure";
      RestartSec = "10s";
      StartLimitBurst = 3;
      StartLimitInterval = "120s";
    };
  };
in {
  age.secrets."rclone_config" = {
    file = /${vars.secretsDir}/secrets/users/krumpy-miha/rclone.conf.age;
    path = "${config.xdg.configHome}/rclone/rclone.conf";
  };

  systemd.user.services = lib.mkMerge (
    [
      # Mount services
      {
        "rclone@" = rcloneMountBase;
        "rclone@nextcloud-personal" = lib.recursiveUpdate rcloneMountBase {
          Install.WantedBy = ["default.target"];
        };
      }
    ]
    # Bisync services
    ++ (map (svc: {
        "rclone-bisync-${svc.name}" = (mkBisyncService svc).service;
      })
      bisyncServices)
  );

  # Bisync timers
  systemd.user.timers = builtins.listToAttrs (map (svc: {
      name = "rclone-bisync-${svc.name}";
      value = (mkBisyncService svc).timer;
    })
    bisyncServices);
}

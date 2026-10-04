{
  ...
}:
{
  home.storage-mount = {
    homeManager =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        rcloneConfigPath = config.age.secrets."rclone_config".path;

        rcloneMountBase = {
          # Template unit rclone@.service; rclone@nextcloud-personal is
          # enabled at login. Executables are store/wrapper-absolute.
          Unit = {
            Description = "rclone: Remote FUSE filesystem for cloud storage config %i";
            Documentation = "man:rclone(1)";
            After = [
              "network-online.target"
              "agenix.service"
            ];
            Wants = [ "network-online.target" ];
            StartLimitIntervalSec = "120s";
            StartLimitBurst = 3;
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
                --config=${rcloneConfigPath} \
                --dir-cache-time 1m0s \
                --poll-interval 30s \
                --vfs-cache-mode full \
                --vfs-cache-max-size 2G \
                --vfs-cache-poll-interval 30s \
                --log-level INFO \
                --umask 022 \
                --allow-other \
                %i: %h/mnt/%i
            ''; # No --log-file: output reaches the (size-capped) journal via
            # stderr; /tmp would leak the browsed file inventory world-readably.
            # Debug with "-vv \"
            ExecStop = "/run/wrappers/bin/fusermount -u %h/mnt/%i";
            # NixOS patch
            Environment = [ "PATH=/run/wrappers/bin/:$PATH" ];
            # Restart settings
            Restart = "on-failure";
            RestartSec = "10s";
          };
        };
      in
      {
        # Mount remote storage
        # home-manager does not have overrideStrategy, so we have to improvise
        # rclone listremotes
        config.systemd.user.services = {
          # Mount services
          "rclone@" = rcloneMountBase;
          "rclone@nextcloud-personal" = lib.recursiveUpdate rcloneMountBase {
            Install.WantedBy = [ "default.target" ];
          };
        };
      };
  };
}

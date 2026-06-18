{ ... }:
{
  den.aspects.containers = {
    nixos =
      { pkgs, ... }:
      {

        # Enable containers

        virtualisation.docker = {
          enable = true;
          package = pkgs.docker_29; # v29 is just more broken with every single release # now this is the only wersion available, hopefully it will work
          storageDriver = "btrfs"; # All hosts use btrfs root; containerd overlayfs snapshotter is incompatible with btrfs
          daemon = {
            settings = {
              log-level = "warn"; # "debug"|"info"|"warn"|"error"|"fatal" (default "info")
              live-restore = true;
              registry-mirrors = [ "https://mirror.gcr.io" ];
              #features.containerd-snapshotter = false; # Disable containerd image store — its overlayfs snapshotter fails on btrfs with "no such device"
            };
          };
        };

        # Add required users to group "docker"
      };
  };
}

{ ... }:
{
  den.aspects.docker = {
    nixos =
      { ... }:
      {
        imports = [ ./_container-runtime.nix ];

        # Enable containers

        virtualisation.docker = {
          enable = true;
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

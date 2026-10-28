{ ... }:
{
  den.aspects.docker = {
    nixos =
      { pkgs, ... }:
      {
        imports = [ ./_container-runtime.nix ];

        # Enable containers

        virtualisation.docker = {
          enable = true;
          daemon = {
            settings = {
              log-level = "warn"; # "debug"|"info"|"warn"|"error"|"fatal" (default "info")
              live-restore = true;
              registry-mirrors = [ "https://mirror.gcr.io" ];
              #features.containerd-snapshotter = false; # Disable containerd image store — its overlayfs snapshotter fails on btrfs with "no such device"
            };
          };
        };

        environment.systemPackages = with pkgs; [
          lazydocker # TUI for Docker container management
        ];

        # Add required users to group "docker"
      };
  };
}

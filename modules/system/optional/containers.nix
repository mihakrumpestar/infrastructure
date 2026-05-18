{ ... }:
{
  den.aspects.containers = {
    nixos =
      { pkgs, ... }:
      {

        # Enable containers

        virtualisation.docker = {
          enable = true;
          package = pkgs.docker_28; # v29 is just more broken with every single release
          daemon = {
            settings = {
              log-level = "warn"; # "debug"|"info"|"warn"|"error"|"fatal" (default "info")
              live-restore = true;
              registry-mirrors = [ "https://mirror.gcr.io" ];
            };
          };
        };

        # Add required users to group "docker"
      };
  };
}

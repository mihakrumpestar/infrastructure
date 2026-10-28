{ lib, ... }:
{
  den.aspects.podman = {
    nixos =
      {
        pkgs,
        ...
      }:
      {
        imports = [ ./_container-runtime.nix ];

        virtualisation.podman = {
          enable = true;
          # Timer: podman system prune -f weekly (autoPrune.dates); removes stopped containers, unused networks, dangling images/cache; flags append.
          autoPrune.enable = true;
        };

        # Lazydocker against the rootful podman Docker-API socket (users need
        # the podman group). Lazydocker honours DOCKER_HOST.
        environment.systemPackages = [
          (pkgs.writeShellScriptBin "lazypodman" ''
            export DOCKER_HOST="unix:///run/podman/podman.sock"
            exec ${lib.getExe pkgs.lazydocker} "$@"
          '')
        ];

        # Quiet the podman API service
        systemd.services.podman.environment.LOGGING = lib.mkForce "--log-level=warn";

      };
  };
}

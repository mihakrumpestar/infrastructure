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

        # Native btrfs storage driver (docker stance in docker.nix);
        # must be set before first use, switching later orphans images.
        virtualisation.containers.storage.settings.storage.driver = "btrfs";

        # Not set by the nixpkgs podman module; needed by netavark and the
        # CNI bridge/portmap plugins. dockerd writes its own at runtime.
        boot.kernel.sysctl = {
          "net.bridge.bridge-nf-call-iptables" = 1;
          "net.bridge.bridge-nf-call-ip6tables" = 1;
        };
      };
  };
}

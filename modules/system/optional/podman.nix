{ ... }:
{
  den.aspects.podman = {
    nixos =
      { ... }:
      {
        imports = [ ./_container-runtime.nix ];

        virtualisation.podman = {
          enable = true;
          autoPrune.enable = true;
        };

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

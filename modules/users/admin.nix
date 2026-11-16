{ inputs, ... }:
{
  den.aspects.admin = {
    nixos =
      {
        config,
        lib,
        ...
      }:
      {
        # Only the servers run this aspect, so only they receive the hash.
        sops.secrets.admin_hashedPassword = {
          sopsFile = "${inputs.infrastructure-secrets}/secrets/sops/servers.yaml";
          key = "admin/hashed_password";
          neededForUsers = true;
        };

        users.users.admin = {
          isNormalUser = true;
          isSystemUser = false;
          linger = true;
          uid = lib.mkForce 1001;
          group = "users";
          extraGroups = [
            "wheel"
            "podman"
            "libvirtd"
            "kvm"
            "tss"
            "netbird" # NetBird control socket access (services.netbird in networking.nix)
          ];
          hashedPasswordFile = config.sops.secrets.admin_hashedPassword.path;
          openssh.authorizedKeys.keys = [ ];
        };

        security.sudo.wheelNeedsPassword = false;
      };
  };
}

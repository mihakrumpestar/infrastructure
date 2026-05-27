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
        age.secrets."admin_hashedPassword" = {
          file = "${inputs.infrastructure-secrets}/secrets/users/root/admin_hashedPassword.age";
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
          ];
          hashedPasswordFile = config.age.secrets."admin_hashedPassword".path;
          openssh.authorizedKeys.keys = [ ];
        };

        security.sudo.wheelNeedsPassword = false;
      };
  };
}

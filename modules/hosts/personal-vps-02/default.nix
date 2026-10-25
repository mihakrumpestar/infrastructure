{ den, inputs, ... }:
let
  secretsDir = inputs.infrastructure-secrets;
  data = import "${secretsDir}/secrets/users/root/data.nix";
in
{
  den.aspects.personal-vps-02 = {
    includes = [
      den.aspects.server
      den.aspects.vm-guest
      den.aspects.nomad
    ];
    nixos =
      { lib, ... }:
      {
        /*
          Hardware:
            KVM Server (VPS 1000 G12 Pro)
            AMD EPYC-Genoa (4/4)
            8 GB RAM
            510 GB SATA SSD - boot and data
        */

        imports = [ ./_hardware-configuration.nix ];

        my = {
          disks = {
            bootLoader = "grub";
            bootDisk = "/dev/vda";
            swapSize = null; # No swap
          };

          nomad.enable = true;
        };

        users.users.root.openssh.authorizedKeys.keys = lib.mkForce [
          data.ssh_authorized_keys.vps
        ];
      };
  };
}

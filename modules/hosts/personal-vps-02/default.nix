{ den, ... }:
{
  den.aspects.personal-vps-02 = {
    includes = [
      den.aspects.server
      den.aspects.vm-guest
      den.aspects.nomad
    ];
    nixos =
      { ... }:
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
            platform = "guest";
            bootDisk = "/dev/vda";
          };

          # disable since we are using ext4
          impermanence.enable = false;

          nomad.enable = true;
        };
      };
  };
}

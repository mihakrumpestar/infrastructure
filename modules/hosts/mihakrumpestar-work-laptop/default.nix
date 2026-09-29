{ den, lib, ... }:
{
  den.aspects.mihakrumpestar-work-laptop = {
    includes = [
      den.aspects.client
      den.aspects.docker
      den.aspects.podman
      den.aspects.virtualization
      den.aspects.nomad
    ];
    nixos =
      { ... }:
      {
        /*
          Hardware:
            Thinkpad T16 Gen 3
            Intel Core Ultra 5 125U
            16 GB RAM
            512 GB NVMe SSD
        */

        imports = [ ./_hardware-configuration.nix ];

        my = {
          disks = {
            bootDisk = "/dev/nvme0n1";
            swapSize = "16G";
            encryptRoot = "fido2";
          };

          nomad.enable = true;
        };

        home-manager.users."krumpy-miha" = {
          my.home.fullAutostart.enable = true;
        };

        security.lockKernelModules = lib.mkForce false; # Disable for more rapid experimentation
      };
  };
}

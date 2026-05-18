{ den, ... }:
{
  den.aspects.personal-laptop = {
    includes = [
      den.aspects.client
      den.aspects.containers
      den.aspects.virtualization
    ];
    nixos =
      { ... }:
      {
        /*
          Hardware:
            HP 255 15.6 inch G10 Notebook PC
            AMD Ryzen 5 7530U
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

          networking.homeWifi.enable = true;
        };
      };
  };
}

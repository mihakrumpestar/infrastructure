{ den, ... }:
{
  den.aspects.kiosk = {
    includes = [ den.aspects.client ];
    nixos =
      { ... }:
      {
        /*
          Hardware:
            81SS (Lenovo IdeaPad FLEX-14API)
            AMD Ryzen 5 3500U
            12 GB RAM
            256 GB NVMe SSD
        */

        imports = [ ./_hardware-configuration.nix ];

        my = {
          disks = {
            bootDisk = "/dev/nvme0n1";
            swapSize = "16G";
            encryptRoot = "tpm2";
          };

          networking.homeWifi.enable = true;

          de.plasma.kiosk = true;

          impermanence.fullyImpermanent = true;

          # Lanzaboote + measured boot require several state files to survive
          impermanence.directories = [
            "/var/lib/sbctl"
            "/var/lib/pcrlock.d"
            "/var/lib/auto-cryptenroll"
            "/var/lib/systemd" # pcrlock.json lives here, can't mount as file as it is overwritten
          ];
        };
      };
  };
}

{ den, ... }:
{
  den.aspects.personal-workstation = {
    includes = [
      den.aspects.client
      den.aspects.containers
      den.aspects.virtualization

      den.aspects.backup
      den.aspects.dead-mens-switch
    ];
    nixos =
      { lib, pkgs, ... }:
      {
        /*
          Hardware:
            MoreFine S500+
            AMD Ryzen 9 5900HX
            32 GB RAM
            512 GB NVMe SSD
        */

        imports = [ ./_hardware-configuration.nix ];

        my = {
          disks = {
            bootDisk = "/dev/nvme0n1";
            swapSize = "32G";
            encryptRoot = "fido2";
          };

          networking.homeWifi.enable = true;
        };

        nix.gc.automatic = lib.mkForce false; # Disable, since this is our builder

        home-manager.users."krumpy-miha" = {
          my.home.fullAutostart.enable = true;
        };

        # git clone https://github.com/FAForever/faf-linux
        # cd faf-linux
        # steam-run bash
        # ./setup.sh
        # ./run
        # ./run-offline
        programs.steam = {
          enable = true;
          package =
            with pkgs;
            steam.override {
              # deadnix: skip
              extraPkgs = pkgs: [
                jq
                cabextract
                wget
                pkgsi686Linux.libpulseaudio
                pkgsi686Linux.freetype
                pkgsi686Linux.libxcursor
                pkgsi686Linux.libxcomposite
                pkgsi686Linux.libxi
                pkgsi686Linux.libxrandr
              ];
            };
        };
      };
  };
}

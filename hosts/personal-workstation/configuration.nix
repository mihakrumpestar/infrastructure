{
  lib,
  pkgs,
  ...
}: {
  my = {
    disks = {
      bootDisk = "/dev/nvme0n1";
      swapSize = "32G";
      encryptRoot = "fido2";
    };

    hostType = "client";

    networking.homeWifi.enable = true;

    de.plasma.enable = true;

    users = ["krumpy-miha"];
  };

  nix = {
    gc = {
      automatic = lib.mkForce false; # Disable, since this is our builder
    };
  };

  home-manager.users."krumpy-miha" = {
    my.home = {
      fullAutostart.enable = true;
      backup.enable = true;
      dead-mens-switch.enable = true;
    };
  };

  # git clone https://github.com/FAForever/faf-linux
  # cd faf-linux
  # steam-run bash
  # ./setup.sh
  # .run
  # .run-offline
  programs.steam = {
    enable = true;
    package = with pkgs;
      steam.override {
        # deadnix: skip
        extraPkgs = pkgs: [
          jq
          cabextract
          wget
          pkgsi686Linux.libpulseaudio
          pkgsi686Linux.freetype
          pkgsi686Linux.xorg.libXcursor
          pkgsi686Linux.xorg.libXcomposite
          pkgsi686Linux.xorg.libXi
          pkgsi686Linux.xorg.libXrandr
        ];
      };
  };
}

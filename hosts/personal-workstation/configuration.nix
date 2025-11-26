{lib, ...}: {
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
}

{...}: {
  imports = [
    ./brightness.nix
  ];

  my = {
    disks = {
      bootDisk = "/dev/nvme0n1"; #"/dev/mmcblk0";
      swapSize = "8G";
      encryptRoot = "tpm2";
    };

    hostType = "client";
    hostSubType = "kiosk";

    networking.homeWifi.enable = true;

    users = ["kiosk"];

    de.plasma.enable = true;
  };
}

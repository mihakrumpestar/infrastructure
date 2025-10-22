{pkgs, ...}: {
  my = {
    disks = {
      bootDisk = "/dev/mmcblk0";
      swapSize = "4G";
      encryptRoot = "tpm2";
    };

    hostType = "client";
    hostSubType = "kiosk";

    de.plasma.enable = true;
  };

  users.users.kiosk = {
    isNormalUser = true;
    linger = true;
    extraGroups = [
      "networkmanager"
    ];
  };

  services.displayManager = {
    autoLogin.enable = true;
    autoLogin.user = "kiosk";
  };

  # Out-of-tree kernel module for touchscreen
  hardware.firmware = [
    (
      let
        gsl-firmware = pkgs.fetchFromGitHub {
          owner = "onitake";
          repo = "gsl-firmware";
          rev = "c180b35763433a61ca29740860940dc789c1b2e2";
          sha256 = "sha256-+iGrI3y/Jw0G1cPDRxrKeFcMIIFIGBORC9oOt/2W+7U=";
        };
      in
        pkgs.runCommandNoCC "gsl-firmware" {} ''
          mkdir -p $out/lib/firmware/silead
          cp ${gsl-firmware}/firmware/chuwi/hi10_plus/silead_ts.fw $out/lib/firmware/silead/mssl0017.fw
        ''
    )
  ];

  boot.kernelModules = ["silead_ts"];
}

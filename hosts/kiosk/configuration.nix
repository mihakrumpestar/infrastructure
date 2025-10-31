{...}: {
  imports = [
    ./brightness.nix
  ];

  my = {
    disks = {
      bootDisk = "/dev/nvme0n1";
      swapSize = "16G";
      encryptRoot = "tpm2";
    };

    hostType = "client";
    hostSubType = "kiosk";

    networking.homeWifi.enable = true;

    users = ["kiosk"];

    de.plasma.enable = true;
  };

  # Out-of-tree kernel module for touchscreen
  # dmesg | grep i2c
  #hardware.firmware = [
  #  (
  #    let
  #      gsl-firmware = pkgs.fetchFromGitHub {
  #        owner = "onitake";
  #        repo = "gsl-firmware";
  #        rev = "c180b35763433a61ca29740860940dc789c1b2e2";
  #        sha256 = "sha256-+iGrI3y/Jw0G1cPDRxrKeFcMIIFIGBORC9oOt/2W+7U=";
  #      };
  #    in
  #      pkgs.runCommand "gsl-firmware" {} ''
  #        mkdir -p $out/lib/firmware/silead
  #        cp ${gsl-firmware}/firmware/chuwi/hi10_plus/firmware.fw $out/lib/firmware/silead/mssl0017.fw
  #      ''
  #  )
  #]; #
  #boot = {
  #  kernelModules = ["silead_ts"];
  #};
  #
  #services.udev = {
  #  # Based on: https://github.com/samueldr/mobile-nixos-extra-devices/blob/78748578253347f72c1ba7997aeef4badedb767b/devices/chuwi-hi10prohq64/kernel/0001-HACK-Bake-in-touchscreen-tranformation-matrix.patch
  #  extraRules = ''
  #    ACTION=="add|change", KERNEL=="event*", ATTRS{name}=="*silead*", ENV{LIBINPUT_CALIBRATION_MATRIX}="2.15 0 -0.04 0 3.23 -0.01"
  #    ACTION=="add|change", KERNEL=="event*", ATTRS{name}=="*gsl*", ENV{LIBINPUT_CALIBRATION_MATRIX}="2.15 0 -0.04 0 3.23 -0.01"
  #    ACTION=="add|change", KERNEL=="event*", ATTRS{name}=="*touch*", ENV{LIBINPUT_CALIBRATION_MATRIX}="2.15 0 -0.04 0 3.23 -0.01"
  #  '';
  #};
}

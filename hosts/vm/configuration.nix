{
  my = {
    disks = {
      bootDisk = "/dev/vda";
      encryptRoot = false;
    };

    hostType = "client";
  };

  services.qemuGuest.enable = true;

  #host.users = [
  #  "krumpy-miha"
  #];

  de.plasma.enable = true;
}

{
  disks = {
    bootDisk = "/dev/vda";
    encryptRoot = true;
  };

  services.qemuGuest.enable = true;

  #host.users = [
  #  "krumpy-miha"
  #];

  de.plasma.enable = true;
}

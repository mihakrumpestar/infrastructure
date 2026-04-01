{
  config,
  lib,
  ...
}: let
  store-secrets = config.my.store-secrets.secrets;
in {
  /*
  Hardware:
    KVM Server (VPS 1000 G12 Pro)
    AMD EPYC-Genoa (4/4)
    8 GB RAM
    510 GB SATA SSD - boot and data
  */

  my = {
    disks = {
      bootLoader = "grub";
      bootDisk = "/dev/vda";
      swapSize = "2G";
    };

    hostType = "server";
    hostSubType = "vm";
  };

  networking.interfaces.eth0.useDHCP = true;

  users.users.root.openssh.authorizedKeys.keys = lib.mkForce [
    store-secrets."ssh_authorized_keys".vps
  ];
}

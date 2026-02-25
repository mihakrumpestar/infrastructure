{
  config,
  lib,
  ...
}: let
  store-secrets = config.my.store-secrets.secrets;
in {
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

  services.qemuGuest.enable = true;
  services.spice-vdagentd.enable = true;

  users.users.root.openssh.authorizedKeys.keys = lib.mkForce [
    store-secrets."ssh_authorized_keys".vps
  ];
}

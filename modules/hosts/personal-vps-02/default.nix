{ den, inputs, ... }:
let
  data = import "${inputs.infrastructure-secrets}/secrets/users/root/data.nix";
in
{
  den.aspects.personal-vps-02 = {
    includes = [
      den.aspects.server
      den.aspects.vm-guest
    ];
    nixos =
      { lib, ... }:
      {
        /*
          Hardware:
            KVM Server (VPS 1000 G12 Pro)
            AMD EPYC-Genoa (4/4)
            8 GB RAM
            510 GB SATA SSD - boot and data
        */

        imports = [ ./_hardware-configuration.nix ];

        my = {
          disks = {
            bootLoader = "grub";
            bootDisk = "/dev/vda";
            swapSize = "2G";
          };
        };

        # For systemd-networkd-wait-online to work properly
        systemd.network = {
          links."10-wan0" = {
            matchConfig.Type = "ether";
            linkConfig.Name = "wan0";
          };
          networks."40-wan0" = {
            matchConfig.Name = "wan0";
            networkConfig.DHCP = "yes";
            linkConfig.RequiredForOnline = "routable";
          };
        };

        users.users.root.openssh.authorizedKeys.keys = lib.mkForce [
          data.ssh_authorized_keys.vps
        ];
      };
  };
}

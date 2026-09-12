{ den, inputs, ... }:
let
  secretsDir = inputs.infrastructure-secrets;
  data = import "${secretsDir}/secrets/users/root/data.nix";
in
{
  den.aspects.personal-vps-02 = {
    includes = [
      den.aspects.server
      den.aspects.vm-guest
      den.aspects.nomad
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
            swapSize = null; # No swap
          };

          nomad.enable = true;
        };

        # For systemd-networkd-wait-online to work properly
        systemd.network = {
          # Match by MAC to avoid catching container veth interfaces
          # (podman/CNI), which are also Type=ether
          links."10-wan0" = {
            matchConfig.PermanentMACAddress = "ca:d1:23:02:a1:e3";
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

{ den, inputs, ... }:
let
  secretsDir = inputs.infrastructure-secrets;
  data = import "${secretsDir}/secrets/users/root/data.nix";
  hostData = import "${secretsDir}/secrets/data.nix";
  host = hostData.hosts.personal-vps-02;
in
{
  den.aspects.personal-vps-02 = {
    includes = [
      den.aspects.server
      den.aspects.vm-guest
      den.aspects.rke2
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
            swapSize = null; # Disabled, RKE2/Kubernetes requires no swap
          };

          rke2 = {
            enable = true;

            # Extra TLS SANs beyond the default hostname and 127.0.0.1.
            # Public IP for external/multi-cluster access.
            tlsSans = [ host.nics.default.ip ];

            # Public IPs of all cluster nodes. Used to restrict firewall rules
            # for internal ports (9345, 10250, 2379-2381, 5001) to cluster
            # nodes only. Add more nodes here when expanding.
            nodeAddresses = [ host.nics.default.ip ];

            # Cluster join token
            tokenSecretFile = "${secretsDir}/secrets/services/rke2/cluster-01/rke2-token.age";
          };
        };

        # For systemd-networkd-wait-online to work properly
        systemd.network = {
          # Match by MAC to avoid catching Calico cali* veth interfaces
          # which are also Type=ether
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

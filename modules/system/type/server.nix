{ den, inputs, ... }:
let
  data = import "${inputs.infrastructure-secrets}/secrets/users/root/data.nix";
in
{
  den.aspects.server = {
    includes = [ den.aspects.admin ];
    nixos =
      { ... }:
      {
        users.users.root.openssh.authorizedKeys.keys = [
          data.ssh_authorized_keys.server
        ];

        # All NixOS servers are VPSes or VMs, so the uplink is DHCP-only.
        # Matches every physical ethernet NIC regardless of its name, and
        # excludes all virtual kinds via Kind = "!*": physical NICs have no
        # kind, while veth/bridge/tun/etc report one (container veths are
        # Type=ether but Kind=veth).
        #
        # https://wiki.nixos.org/wiki/Systemd/networkd
        # Test: networkctl
        systemd.network = {
          enable = true;

          networks."40-wan" = {
            matchConfig = {
              Type = "ether";
              Kind = "!*";
            };
            networkConfig.DHCP = "yes";
            # Required so systemd-networkd-wait-online gates boot on routability
            linkConfig.RequiredForOnline = "routable";
          };
        };

        networking.useDHCP = false;
      };
  };
}

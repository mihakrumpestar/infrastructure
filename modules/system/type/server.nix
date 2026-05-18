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

        # https://wiki.nixos.org/wiki/Systemd/networkd
        # https://astro.github.io/microvm.nix/simple-network.html
        # Test:
        # networkctl
        systemd.network = {
          enable = true;
          netdevs = {
            "20-br0" = {
              netdevConfig = {
                Kind = "bridge";
                Name = "br0";
              };
            };
          };
        };

        networking.useDHCP = false;
      };
  };
}

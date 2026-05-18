{ den, inputs, ... }:
let
  data = import "${inputs.infrastructure-secrets}/secrets/users/root/data.nix";
in
{
  den.aspects.client = {
    includes = [
      den.aspects.plasma
      den.aspects.peripherals
    ];
    nixos =
      { ... }:
      {
        # Networking
        networking.networkmanager.enable = true;

        users.users.root.openssh.authorizedKeys.keys = [
          data.ssh_authorized_keys.client
        ];
      };
  };
}

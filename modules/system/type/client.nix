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
      {
        config,
        lib,
        pkgs,
        ...
      }:
      {
        # Networking
        networking.networkmanager = {
          enable = true;

          # OpenVPN support for the NM clients
          plugins = [ pkgs.networkmanager-openvpn ];
        };

        # nm-online -s waits for ALL devices to be activated or failed, which
        # blocks boot for ~30s on interfaces with no cable. Without -s, it
        # returns as soon as any interface is connected.
        systemd.services.NetworkManager-wait-online.serviceConfig.ExecStart =
          lib.mkForce "${config.networking.networkmanager.package}/bin/nm-online -q";

        users.users.root.openssh.authorizedKeys.keys = [
          data.ssh_authorized_keys.client
        ];
      };
  };
}

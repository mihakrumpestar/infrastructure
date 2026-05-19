{ den, ... }:
{
  den.aspects.vm-guest = {
    includes = [ den.aspects.admin ];
    nixos =
      { ... }:
      {
        services = {
          qemuGuest.enable = true;
          spice-vdagentd.enable = true;
        };

        # users.users.root.openssh.authorizedKeys.keys set in host, as they may be in homelab or as a VPS

        # VM guests use SSH host keys as age identity (TPM is not available)
        my.secrets.useTpm = false;
      };
  };
}

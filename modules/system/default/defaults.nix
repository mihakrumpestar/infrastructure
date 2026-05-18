{ ... }:
{
  den.aspects.defaults = {
    nixos =
      { config, ... }:
      {
        system.stateVersion = config.system.nixos.release;
      };
  };
}

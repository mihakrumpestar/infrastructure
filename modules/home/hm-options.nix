{ ... }:
{
  den.aspects.hm-options = {
    nixos =
      { lib, ... }:
      {
        home-manager.sharedModules = [
          {
            options.my.home.fullAutostart.enable = lib.mkEnableOption "Autostart apps";
          }
        ];
      };
  };
}

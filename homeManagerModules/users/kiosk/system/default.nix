{
  config,
  lib,
  ...
}:
with lib; let
  username = builtins.baseNameOf (builtins.dirOf (builtins.toString ./.));
in {
  imports = [
    ./brightness.nix
  ];

  config = mkIf (builtins.elem username config.my.users) {
    services.displayManager = {
      autoLogin = {
        enable = true;
        user = username;
      };
    };
  };
}

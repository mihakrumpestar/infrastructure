{
  config,
  lib,
  username,
}:
with lib; {
  config = mkIf (builtins.elem username config.my.users) {
    services.displayManager = {
      autoLogin.enable = true;
      autoLogin.user = username;
    };
  };
}

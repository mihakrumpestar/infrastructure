{
  config,
  lib,
  vars,
  ...
}:
with lib; let
  # Users that should be enabled and imported
  enabledUsers = config.my.users;
in {
  options.my.users = mkOption {
    type = types.listOf types.str;
    default = [];
    description = "List of users to enable and import";
  };

  config = mkIf (enabledUsers != []) {
    users.users = builtins.listToAttrs (
      map (username: {
        name = username;
        value = {
          isNormalUser = true;
          linger = true; # Make sure user services are started on boot
          # initialHashedPassword = "something"; # Generate using: mkpasswd
          # Remove password: passwd -d username
          extraGroups = [
            "networkmanager"
          ];
        };
      })
      enabledUsers
    );

    home-manager.users = builtins.listToAttrs (
      map (username: {
        name = username;
        value = {
          my.store-secrets = {
            enable = true;
            secretsFile = "${vars.secretsDir}/secrets/users/${username}/store-secrets.nix";
          };

          imports = [(./. + "/${username}/home")];
        };
      })
      enabledUsers
    );
  };
}

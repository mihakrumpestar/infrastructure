{
  config,
  lib,
  vars,
  pkgs,
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

  # Import system modules - but only import those that exist to avoid errors during early evaluation
  #imports =
  #  map (username: ./. + "/${username}/system")
  #  (lib.filter (username: builtins.pathExists (./. + "/${username}/system")) enabledUsers);

  # TODO: above code gives infinite recursion, so we have to specify user systems manualy
  imports = [
    (import ./krumpy-miha/system {
      username = "krumpy-miha";
      inherit config lib pkgs;
    })
    (import ./kiosk/system {
      username = "kiosk";
      inherit config lib pkgs;
    })
  ];

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

          # Pass username to system modules via special argument
          _module.args.username = username;
        };
      })
      enabledUsers
    );
  };
}

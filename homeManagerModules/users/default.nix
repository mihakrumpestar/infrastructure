{
  config,
  lib,
  vars,
  ...
}: let
  userDirs = builtins.attrNames (builtins.readDir ./.);
  availableUsers = builtins.filter (name: name != "default.nix" && builtins.pathExists (./. + "/${name}/system/default.nix")) userDirs;

  # Static UID mappings for impermanence (required for correct ownership during nixos-install)
  userUid = {
    "krumpy-miha" = 1000;
    "admin" = 1001;
    "kiosk" = 1002;
  };
in {
  options.my.users = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [];
    description = "List of users to enable and import";
  };

  imports = map (username: (./. + "/${username}/system")) availableUsers;

  config = lib.mkIf (config.my.users != []) {
    users.groups."users".gid = 100;

    users.users = lib.genAttrs config.my.users (username: {
      isNormalUser = true;
      linger = true; # Make sure user services are started on boot

      group = "users";
      uid = lib.mkDefault userUid.${username};

      # initialHashedPassword = "something"; # Generate using: mkpasswd
      # Remove password: passwd -d username
      openssh.authorizedKeys.keys = [
        config.my.store-secrets.secrets."ssh_authorized_keys".${config.my.hostType} # Allow administrator to login as any user
      ];
      extraGroups = [
        "networkmanager"
      ];
    });

    home-manager.users = lib.genAttrs config.my.users (username: {
      my.store-secrets = {
        enable = true;
        secretsFile = "${vars.secretsDir}/secrets/users/${username}/store-secrets.nix";
      };

      imports = [(./. + "/${username}/home")];

      # Pass username to system modules via special argument
      _module.args.username = username;
    });
  };
}

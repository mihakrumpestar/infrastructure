{ inputs, ... }:
let
  secretsDir = inputs.infrastructure-secrets;
  cache = import "${secretsDir}/secrets/services/nix-cache/config.nix";

  cacheUrl = "s3://${cache.bucket}?region=${cache.region}&endpoint=${cache.endpoint}";
in
{
  den.aspects.nix-cache = {
    nixos =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        credentialsPath = config.age.secrets."nix-cache-aws-credentials".path;
        signingKeyPath = config.age.secrets."nix-cache-signing-key".path;

        # Builders are root and members of this group. wheel already is in
        # trusted-users, which post-build-hook requires. A separate group
        # would not add isolation: wheel members can sudo to root anyway.
        builderGroup = "wheel";

        isBuilder = name: user: name == "root" || builtins.elem builderGroup (user.extraGroups or [ ]);

        # Runs from nix-daemon as root. The hook sets its own credentials,
        # HOME and signing key so it also works when root builds without the
        # daemon. A failed upload is logged but never fails the build or
        # blocks later builds.
        uploadHook = pkgs.writeShellScript "nix-cache-upload" ''
          set -u
          set -f
          export IFS=' '

          unset NIX_REMOTE
          export HOME=/root
          export AWS_SHARED_CREDENTIALS_FILE=${lib.escapeShellArg credentialsPath}

          if [ -z "''${OUT_PATHS:-}" ]; then
            exit 0
          fi

          if ! ${config.nix.package}/bin/nix copy \
            --to ${lib.escapeShellArg "${cacheUrl}&secret-key=${signingKeyPath}"} \
            $OUT_PATHS; then
            echo "nix-cache: upload failed for $OUT_PATHS" >&2
          fi

          exit 0
        '';

        hookConf = pkgs.writeText "nix-cache-hook.conf" ''
          post-build-hook = /etc/nix-cache-upload
        '';

        # Home Manager owns ~/.config/nix/nix.conf for its users, so only the
        # remaining builders get a file from tmpfiles.
        hookUsers = lib.filterAttrs (
          name: user:
          isBuilder name user && !(builtins.hasAttr name config.home-manager.users) && user.home != null
        ) config.users.users;

        hookUserRules = lib.concatLists (
          lib.mapAttrsToList (name: user: [
            "d ${user.home}/.config 0755 ${name} ${user.group} -"
            "d ${user.home}/.config/nix 0700 ${name} ${user.group} -"
            "L+ ${user.home}/.config/nix/nix.conf - - - - ${hookConf}"
          ]) hookUsers
        );
      in
      {
        age.secrets."nix-cache-aws-credentials" = {
          file = "${secretsDir}/secrets/services/nix-cache/aws-credentials.age";
          owner = "root";
          group = "root";
          mode = "0400";
        };

        age.secrets."nix-cache-signing-key" = {
          file = "${secretsDir}/secrets/services/nix-cache/signing-key.age";
          owner = "root";
          group = "root";
          mode = "0400";
        };

        environment.etc."nix-cache-upload".source = uploadHook;

        nix.settings = {
          substituters = [ cacheUrl ];
          trusted-public-keys = [ cache.publicKey ];
          secret-key-files = [ signingKeyPath ];
        };

        # nix-daemon runs as root and resolves credentials through the AWS
        # SDK's shared credentials file. HOME is not set for system
        # services, so point the SDK at the decrypted agenix secret.
        systemd.services.nix-daemon = {
          after = [ "agenix-install-secrets.service" ];
          environment = {
            HOME = "/root";
            AWS_SHARED_CREDENTIALS_FILE = credentialsPath;
          };
        };

        systemd.tmpfiles.rules = hookUserRules;

        home-manager.sharedModules = [
          (
            {
              config,
              osConfig,
              lib,
              ...
            }:
            let
              user = osConfig.users.users.${config.home.username} or null;
            in
            lib.mkIf (user != null && isBuilder config.home.username user) {
              nix.settings.post-build-hook = "/etc/nix-cache-upload";
            }
          )
        ];
      };
  };
}

# Same as: users/modules/optional/store-secrets/default.nix
{
  config,
  lib,
  ...
}:
with lib; {
  options.my = {
    store-secrets = {
      secretsFile = mkOption {
        type = types.path;
        default = null;
        description = "File containing the secrets in NIX format";
      };

      secrets = mkOption {
        type = types.attrs;
        description = "Store secrets structure from NIX";
      };
    };
  };

  config = mkIf (config.my.store-secrets.secretsFile != null) {
    assertions = [
      {
        assertion = config.my.store-secrets.secretsFile != null && config.my.store-secrets.secrets != {};
        message = "store-secrets.secretsFile and store-secrets.secrets can't be set at the same time";
      }
    ];

    my.store-secrets.secrets = import config.my.store-secrets.secretsFile; # TODO: change to YAML when this merges: https://github.com/NixOS/nix/pull/7340
  };
}

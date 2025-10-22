# Same as: modules/optional/store-secrets
{
  config,
  lib,
  ...
}:
with lib; {
  # Secrets/config sections that are commited to nix-store, but not in git
  options.my = {
    store-secrets = {
      secretsFile = mkOption {
        type = types.nullOr types.path;
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

    my.store-secrets.secrets = import config.my.store-secrets.secretsFile;
  };
}

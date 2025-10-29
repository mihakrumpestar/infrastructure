{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.my.store-secrets;
in {
  options.my.store-secrets = {
    enable = mkEnableOption "store-secrets module";

    secretsFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "File containing the secrets in NIX format";
    };

    secrets = mkOption {
      type = types.attrs;
      description = "Store secrets structure from NIX";
      readOnly = true;
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.secretsFile != null;
        message = "store-secrets.secretsFile must be configured";
      }
    ];

    my.store-secrets.secrets = import cfg.secretsFile;
  };
}

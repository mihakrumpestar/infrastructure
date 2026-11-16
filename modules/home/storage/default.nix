{
  home,
  inputs,
  ...
}:
let
  secretsDir = inputs.infrastructure-secrets;
in
{
  home.storage = {
    includes = [
      home.storage-bisync
      home.storage-mount
    ];
    homeManager =
      {
        config,
        ...
      }:
      {
        # Shared by the bisync wrapper and the rclone@ mount template: one
        # decrypted rclone.conf for every rclone consumer in this feature.
        sops.secrets.rclone_conf = {
          sopsFile = "${secretsDir}/secrets/sops/krumpy-miha.yaml";
          key = "krumpy-miha/rclone_conf";
          path = "${config.xdg.configHome}/rclone/rclone.conf";
        };
      };
  };
}

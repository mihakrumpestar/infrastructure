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
        age.secrets."rclone_config" = {
          file = "${secretsDir}/secrets/users/krumpy-miha/rclone.conf.age";
          path = "${config.xdg.configHome}/rclone/rclone.conf";
        };
      };
  };
}

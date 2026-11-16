{ inputs, ... }:
let
  secretsDir = inputs.infrastructure-secrets;
in
{
  home.backup = {
    homeManager =
      {
        config,
        pkgs,
        ...
      }:
      {
        home.packages = with pkgs; [
          backrest
        ];

        systemd.user.services.backrest = {
          Unit = {
            Description = "Backrest";
            After = [
              "network.target"
              "graphical-session.target"
            ];
          };
          Service = {
            Type = "simple";
            ExecStart = "${pkgs.backrest}/bin/backrest";
            Restart = "on-failure";
            RestartSec = "10s";
            Environment = "BACKREST_PORT=127.0.0.1:9898";
          };
          Install = {
            WantedBy = [ "graphical-session.target" ];
          };
        };

        sops.secrets.backups_password = {
          sopsFile = "${secretsDir}/secrets/sops/krumpy-miha.yaml";
          key = "krumpy-miha/backups_password";
        };

        home.mutableFile.".config/backrest/config.json".source = pkgs.replaceVars ./config.json {
          inherit (config.home) homeDirectory;
          digital_identity_password_path = config.sops.secrets.backups_password.path;
        };
      };
  };
}

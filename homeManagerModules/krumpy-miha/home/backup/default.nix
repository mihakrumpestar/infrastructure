{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  options.my = {
    home.backup.enable = mkEnableOption "Enable backups";
  };

  config = mkIf config.my.home.backup.enable {
    home.packages = with pkgs; [
      backrest
    ];

    systemd.user.services.backrest = {
      Unit = {
        Description = "ResticWeb";
        After = ["network.target"];
      };

      Service = {
        Type = "simple";
        ExecStart = "${pkgs.backrest}/bin/backrest";
        Restart = "on-failure";
        RestartSec = "10s";

        Environment = "BACKREST_PORT=127.0.0.1:9898";
      };

      Install = {
        WantedBy = ["graphical-session.target"];
      };
    };

    my.home.mutableFile.".config/backrest/config.json".source =
      pkgs.replaceVars
      ./config.json
      {
        inherit (config.home) homeDirectory;
        digital_identity_password_path = config.sops.secrets."backups_password/digital_identity".path;
      };

    sops.secrets = {
      "backups_password/digital_identity" = {};
    };
  };
}

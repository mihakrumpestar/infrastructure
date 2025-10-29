{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  dead-mens-switch = with pkgs;
    writeShellApplication {
      name = "dead-mens-switch";
      runtimeInputs = [
        p7zip
        curl
        coreutils # rm
        jq
        libsecret
        libnotify
      ];
      text = builtins.readFile ./dead-mens-switch.sh;
    };
in {
  options.my = {
    home.dead-mens-switch.enable = mkEnableOption "Enable dead-mens-switch";
  };

  config = mkIf config.my.home.dead-mens-switch.enable {
    home.packages = [
      dead-mens-switch
    ];

    systemd.user.services.dead-mens-switch = {
      Unit = {
        Description = "Dead mens switch Upload Service";
        After = ["network-online.target"];
        Wants = ["network-online.target"];
        Requires = ["dead-mens-switch.timer"];
      };

      Service = {
        Type = "simple";
        ExecStart = "${dead-mens-switch}/bin/dead-mens-switch";
      };
    };

    systemd.user.timers.dead-mens-switch = {
      Unit = {
        Description = "Run dead-mens-switch.service every week";
      };

      Timer = {
        OnCalendar = "weekly";
        Persistent = true;
        OnBootSec = "1m30s";
      };

      Install = {
        WantedBy = ["timers.target"];
      };
    };
  };
}

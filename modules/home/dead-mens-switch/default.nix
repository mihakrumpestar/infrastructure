{ ... }:
{
  home.dead-mens-switch = {
    homeManager =
      {
        pkgs,
        ...
      }:
      let
        dead-mens-switch =
          with pkgs;
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
      in
      {
        home.packages = [
          dead-mens-switch
        ];

        systemd.user.services.dead-mens-switch = {
          Unit = {
            Description = "Dead mens switch Upload Service";
            After = [ "network-online.target" ];
            Wants = [ "network-online.target" ];
            StartLimitIntervalSec = 0;
          };
          Service = {
            Type = "simple";
            ExecStart = "${dead-mens-switch}/bin/dead-mens-switch";
            Restart = "on-failure";
            RestartSec = "5min";
          };
        };

        systemd.user.timers.dead-mens-switch = {
          Unit = {
            Description = "Run dead-mens-switch.service every week";
          };
          Timer = {
            OnCalendar = "weekly";
            Persistent = true;
          };
          Install = {
            WantedBy = [ "timers.target" ];
          };
        };
      };
  };
}

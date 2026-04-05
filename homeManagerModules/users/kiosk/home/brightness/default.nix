{
  config,
  pkgs,
  vars,
  ...
}: let
  brightness-server-script = pkgs.writeText "brightness-server.py" (builtins.readFile ./brightness-server.py);

  brightness-server = pkgs.writeShellApplication {
    name = "brightness-server";
    runtimeInputs = with pkgs; [
      python3
      brightnessctl
    ];
    text = ''
      python3 ${brightness-server-script} "$@"
    '';
  };
in {
  age.secrets.brightness-server-token = {
    file = /${vars.secretsDir}/secrets/users/kiosk/brightness-server-token.age;
    path = "${config.home.homeDirectory}/.agenix/secrets/brightness-server-token";
  };

  home.packages = with pkgs; [
    brightnessctl
    brightness-server
  ];

  systemd.user.services.brightness-server = {
    Unit = {
      Description = "Brightness Control REST API Server";
      After = ["graphical-session.target" "agenix.service"];
      Requires = ["agenix.service"];
    };

    Service = {
      Type = "simple";
      EnvironmentFile = config.age.secrets.brightness-server-token.path;
      ExecStart = "${brightness-server}/bin/brightness-server";
      Restart = "on-failure";
      RestartSec = 5;
    };

    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };
}

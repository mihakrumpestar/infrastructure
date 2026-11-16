{ inputs, ... }:
let
  secretsDir = inputs.infrastructure-secrets;
in
{
  home.kiosk-brightness = {
    homeManager =
      { config, pkgs, ... }:
      let
        brightness-server-script = pkgs.writeText "brightness-server.py" (
          builtins.readFile ./brightness-server.py
        );

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
      in
      {
        sops.secrets.brightness_env = {
          sopsFile = "${secretsDir}/secrets/sops/home-network.yaml";
          key = "kiosk/brightness_env";
        };

        home.packages = with pkgs; [
          brightnessctl
          brightness-server
        ];

        systemd.user.services.brightness-server = {
          Unit = {
            Description = "Brightness Control REST API Server";
            After = [
              "graphical-session.target"
              "sops-nix.service"
            ];
            Requires = [ "sops-nix.service" ];
          };
          Service = {
            Type = "simple";
            EnvironmentFile = config.sops.secrets.brightness_env.path;
            ExecStart = "${brightness-server}/bin/brightness-server";
            Restart = "on-failure";
            RestartSec = 5;
          };
          Install = {
            WantedBy = [ "graphical-session.target" ];
          };
        };
      };
  };
}

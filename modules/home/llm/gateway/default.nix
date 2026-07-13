# Plexus LLM API Gateway
{ inputs, ... }:
let
  secretsDir = inputs.infrastructure-secrets;
in
{
  home.llm-gateway = {
    homeManager =
      { config, pkgs, ... }:
      {
        age.secrets."llm_gateway.env" = {
          file = "${secretsDir}/secrets/users/krumpy-miha/llm_gateway.env.age";
          path = "${config.home.homeDirectory}/.agenix/secrets/llm_gateway.env";
        };

        systemd.user.services.plexus = {
          Unit = {
            Description = "Plexus LLM API Gateway";
            After = [
              "graphical-session.target"
              "network-online.target"
            ];
            Wants = [ "network-online.target" ];
          };
          Service = {
            Type = "simple";
            TimeoutStartSec = 120;
            # Only pull if the image doesn't exist locally; periodic updates
            # are handled by plexus-image-update.timer
            ExecStartPre = "${pkgs.bash}/bin/bash -c '${pkgs.docker}/bin/docker image inspect ghcr.io/mcowger/plexus:latest > /dev/null 2>&1 || ${pkgs.docker}/bin/docker pull ghcr.io/mcowger/plexus:latest'";
            ExecStart =
              let
                envFile = config.age.secrets."llm_gateway.env".path;
                startScript = pkgs.writeShellScript "plexus-start" ''
                  exec ${pkgs.docker}/bin/docker run --rm \
                    --name plexus \
                    --network host \
                    -v "${config.home.homeDirectory}/.local/share/plexus:/app/data" \
                    -e DATABASE_URL="sqlite:///app/data/plexus.db" \
                    -e PORT=4000 \
                    -e HOST=127.0.0.1 \
                    -e LOG_LEVEL=info \
                    --env-file "${envFile}" \
                    ghcr.io/mcowger/plexus:latest
                '';
              in
              "${startScript}";
            ExecStop = "${pkgs.docker}/bin/docker stop plexus";
            Restart = "on-failure";
            RestartSec = 10;
          };
          Install = {
            WantedBy = [ "graphical-session.target" ];
          };
        };

        # Periodically check for plexus image updates without blocking startup
        systemd.user.services.plexus-image-update = {
          Unit = {
            Description = "Pull latest Plexus container image";
            After = [ "network-online.target" ];
            Wants = [ "network-online.target" ];
          };
          Service = {
            Type = "oneshot";
            ExecStart = "${pkgs.docker}/bin/docker pull ghcr.io/mcowger/plexus:latest";
          };
        };

        systemd.user.timers.plexus-image-update = {
          Unit = {
            Description = "Timer: Pull latest Plexus container image";
          };
          Timer = {
            OnStartupSec = "5min";
            OnUnitActiveSec = "24h";
          };
          Install = {
            WantedBy = [ "timers.target" ];
          };
        };
      };
  };
}

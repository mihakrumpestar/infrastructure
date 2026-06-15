# Opencode Agent
{ inputs, ... }:
let
  secretsDir = inputs.infrastructure-secrets;
  mattpocockSkillsDir = inputs.mattpocock-skills;

  # Recursively discover all files in a directory and map them to a config prefix
  discoverFiles =
    prefix: dir:
    let
      go =
        path: rel:
        let
          entries = builtins.readDir path;
          process =
            name: type: acc:
            if type == "regular" then
              acc // { "${prefix}/${rel}${name}".source = path + "/${name}"; }
            else if type == "directory" then
              acc // go (path + "/${name}") "${rel}${name}/"
            else
              acc;
        in
        builtins.foldl' (acc: name: process name entries.${name} acc) { } (builtins.attrNames entries);
    in
    go dir "";

  mattpocockSkillConfigs =
    discoverFiles "opencode/skills" (mattpocockSkillsDir + "/skills/engineering")
    // discoverFiles "opencode/skills" (mattpocockSkillsDir + "/skills/productivity");
in
{
  home.llm-agent = {
    homeManager =
      { config, pkgs, ... }:
      let
        opencode-config = pkgs.replaceVars ./opencode.jsonc {
          chromium = "${pkgs.ungoogled-chromium}/bin/chromium";
        };

        localSkillConfigs = discoverFiles "opencode/skills" ./skills;
      in
      {
        age.secrets."llm_agent.env" = {
          file = "${secretsDir}/secrets/users/krumpy-miha/llm_agent.env.age";
          path = "${config.home.homeDirectory}/.agenix/secrets/llm_agent.env";
        };

        home.packages = with pkgs; [
          opencode
          opencode-desktop
        ];

        # Local skills override remote skills on name collision
        xdg.configFile =
          mattpocockSkillConfigs
          // localSkillConfigs
          // {
            "opencode/opencode.json".source = opencode-config;
            "opencode/AGENTS.md".source = ./AGENTS.md;
          };

        # Attach: opencode attach http://localhost:4096
        systemd.user.services.opencode = {
          Unit = {
            Description = "Opencode AI Assistant";
            After = [
              "graphical-session.target"
              "network-online.target"
            ];
            Wants = [ "network-online.target" ];
          };
          Service = {
            Type = "simple";
            TimeoutStartSec = 60;
            WorkingDirectory = "%h";
            ExecStart = "${pkgs.opencode}/bin/opencode serve --hostname 127.0.0.1 --port 4096";
            Environment = "OPENCODE_CONFIG=${opencode-config}";
            EnvironmentFile = [
              config.age.secrets."llm_agent.env".path
              "-/%h/.local/share/opencode/secrets.env"
            ];
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

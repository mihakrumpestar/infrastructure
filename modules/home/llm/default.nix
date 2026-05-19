{ inputs, ... }:
let
  secretsDir = inputs.infrastructure-secrets;
  mattpocockSkillsDir = inputs.mattpocock-skills;

  # Discover skills from a directory: reads subdirectories that contain SKILL.md
  # and generates an attrset suitable for xdg.configFile
  discoverSkills =
    dir:
    let
      entries = builtins.readDir dir;
      isSkillDir = name: type: type == "directory" && builtins.pathExists (dir + "/${name}/SKILL.md");
      skillNames = builtins.filter (name: isSkillDir name entries.${name}) (builtins.attrNames entries);
    in
    builtins.listToAttrs (
      map (name: {
        name = "opencode/skills/${name}/SKILL.md";
        value = {
          source = dir + "/${name}/SKILL.md";
        };
      }) skillNames
    );

  mattpocockSkillConfigs =
    discoverSkills (mattpocockSkillsDir + "/skills/engineering")
    // discoverSkills (mattpocockSkillsDir + "/skills/productivity");
in
{
  den.aspects.hm-llm = {
    homeManager =
      { config, pkgs, ... }:
      let
        opencode-config = pkgs.replaceVars ./opencode.jsonc {
          chromium = "${pkgs.ungoogled-chromium}/bin/chromium";
        };

        skillDir = ./skills;
        localSkillConfigs = discoverSkills skillDir;
      in
      {
        age.secrets."llm_api_keys.env" = {
          rekeyFile = "${secretsDir}/secrets/users/krumpy-miha/llm_api_keys.env.age";
          path = "${config.home.homeDirectory}/.agenix/secrets/llm_api_keys.env";
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
            ".config/opencode/opencode.json".source = opencode-config;
            ".config/opencode/AGENTS.md".source = ./AGENTS.md;
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
            EnvironmentFile = config.age.secrets."llm_api_keys.env".path;
            Restart = "on-failure";
            RestartSec = 5;
          };
          Install = {
            WantedBy = [ "graphical-session.target" ];
          };
        };

        # For "uv"
        home.sessionPath = [
          "${config.home.homeDirectory}/.local/bin"
        ];

        # For OpenCode statistics
        # uv tool install git+https://github.com/Shlomob/ocmonitor-share.git
      };
  };
}

{
  config,
  pkgs,
  vars,
  ...
}: let
  opencode-config =
    pkgs.replaceVars
    ./opencode.jsonc {
      chromium = "${pkgs.ungoogled-chromium}/bin/chromium";
    };

  skillDir = ./skills;
  skillNames = builtins.attrNames (builtins.readDir skillDir);

  localSkillConfigs = builtins.listToAttrs (map (name: {
      name = "opencode/skills/${name}/SKILL.md";
      value = {source = skillDir + "/${name}/SKILL.md";};
    })
    skillNames);

  golang-skill = let
    src = builtins.fetchTarball {
      url = "https://github.com/samber/cc-skills-golang/archive/main.tar.gz";
      sha256 = "0mqbsg2hfrq47271qjd22yqx6a75a2jdyv5bc0f8dsbp35cmf3a0";
    };
    sub_skills = [
      "golang-data-structures"
      "golang-dependency-injection"
      "golang-dependency-management"
      "golang-design-patterns"
      "golang-naming"
      "golang-popular-libraries"
      "golang-safety"
      "golang-stretchr-testify"
      "golang-structs-interfaces"
      "golang-testing"
      "golang-troubleshooting"
    ];
  in
    pkgs.runCommand "golang-skill" {inherit sub_skills;} ''
      mkdir -p $out/references

      first=true
      for name in $sub_skills; do
        skillFile="${src}/skills/$name/SKILL.md"
        if [ "$first" = true ]; then
          cat "$skillFile" > $out/SKILL.md
          first=false
        else
          printf '\n\n---\n\n' >> $out/SKILL.md
          cat "$skillFile" >> $out/SKILL.md
        fi

        refDir="${src}/skills/$name/references"
        if [ -d "$refDir" ]; then
          for f in "$refDir"/*.md; do
            [ -f "$f" ] && cp "$f" $out/references/$name-$(basename "$f")
          done
        fi
      done
    '';
in {
  home.packages = with pkgs; [
    opencode
    opencode-desktop
  ];

  home.mutableFile = {
    ".config/opencode/opencode.json".source = opencode-config;

    # opencode agent list
    ".config/opencode/AGENTS.md".source = ./AGENTS.md;
  };

  xdg.configFile =
    localSkillConfigs
    // {
      "opencode/skills/caveman/SKILL.md".source = builtins.fetchurl {
        url = "https://raw.githubusercontent.com/JuliusBrussee/caveman/main/skills/caveman/SKILL.md";
        sha256 = "0x81fl080nc0yx7424vishq2rqbaqvvmz33ja80w3biv49lj0lf3";
      };

      "opencode/skills/golang/SKILL.md".source = "${golang-skill}/SKILL.md";
      "opencode/skills/golang/references".source = "${golang-skill}/references";
    };

  # Attach: opencode attach http://localhost:4096
  systemd.user.services.opencode = {
    Unit = {
      Description = "Opencode AI Assistant";
      After = [
        "graphical-session.target"
        "network-online.target"
      ];
      Wants = ["network-online.target"];
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
      WantedBy = ["graphical-session.target"];
    };
  };

  # For "uv"
  home.sessionPath = [
    "${config.home.homeDirectory}/.local/bin"
  ];

  # For OpenCode statistics
  # uv tool install git+https://github.com/Shlomob/ocmonitor-share.git

  age.secrets."llm_api_keys.env" = {
    file = /${vars.secretsDir}/secrets/users/krumpy-miha/llm_api_keys.env.age;
    path = "${config.home.homeDirectory}/.agenix/secrets/llm_api_keys.env";
  };
}

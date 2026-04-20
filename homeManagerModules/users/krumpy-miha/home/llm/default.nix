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

      cat > $out/SKILL.md <<'HEADER'
---
name: golang
description: "Comprehensive Go development guide combining best practices for testing, testify assertions and mocks, data structures, dependency injection and management, design patterns, naming, popular libraries, safety, structs/interfaces, and troubleshooting. Use whenever writing Go code, tests, or asking about Go conventions and patterns."
user-invocable: true
license: MIT
compatibility: Designed for Claude Code or similar AI coding agents, and for projects using Golang.
---

**Persona:** You are an expert Go engineer who writes idiomatic, production-ready code. You treat tests as executable specifications and prioritize correctness, readability, and performance.

**Sources:** This skill combines the following sub-skills from [samber/cc-skills-golang](https://github.com/samber/cc-skills-golang):

HEADER

      first=true
      for name in $sub_skills; do
        skillFile="${src}/skills/$name/SKILL.md"
        # Strip YAML frontmatter: skip from first --- to second --- (inclusive)
        body=$(awk 'BEGIN{d=0} /^---$/{d++;next} d>=2' "$skillFile")
        if [ "$first" = true ]; then
          printf '%s\n' "$body" >> $out/SKILL.md
          first=false
        else
          printf '\n\n***\n\n' >> $out/SKILL.md
          printf '%s\n' "$body" >> $out/SKILL.md
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

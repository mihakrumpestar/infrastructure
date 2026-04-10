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
in {
  home.packages = with pkgs; [
    opencode
    opencode-desktop
  ];

  home.mutableFile = {
    ".config/opencode/opencode.json".source = opencode-config;

    # opencode agent list
    ".config/opencode/AGENTS.md".source = ./AGENTS.md;

    # opencode skills
    ".config/opencode/skills/caveman/SKILL.md".source = builtins.fetchurl {
      url = "https://raw.githubusercontent.com/JuliusBrussee/caveman/main/skills/caveman/SKILL.md";
      sha256 = "0x81fl080nc0yx7424vishq2rqbaqvvmz33ja80w3biv49lj0lf3";
    };
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

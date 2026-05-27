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
  home.llm = {
    homeManager =
      { config, pkgs, ... }:
      let
        opencode-config = pkgs.replaceVars ./opencode.jsonc {
          chromium = "${pkgs.ungoogled-chromium}/bin/chromium";
        };

        localSkillConfigs = discoverFiles "opencode/skills" ./skills;
        localCommandConfigs = discoverFiles "opencode/commands" ./commands;
      in
      {
        age.secrets."llm_api_keys.env" = {
          file = "${secretsDir}/secrets/users/krumpy-miha/llm_api_keys.env.age";
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
          // localCommandConfigs
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
            EnvironmentFile = [
              config.age.secrets."llm_api_keys.env".path
              "-/%h/.local/share/opencode/secrets.env"
            ];
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

        # Endpoints:
        # http://localhost:6280 (MCP+server+web dashboard)
        # http://localhost:6280/mcp (streamableHttp)
        # http://localhost:6280/sse (SSE)
        systemd.user.services.docs-mcp-server = {
          Unit = {
            Description = "Docs MCP Server - local documentation index for AI assistants";
            After = [
              "graphical-session.target"
              "network-online.target"
            ];
            Wants = [ "network-online.target" ];
          };
          Service = {
            Type = "simple";
            TimeoutStartSec = 60;
            ExecStart =
              let
                docs-mcp-server-config = (pkgs.formats.yaml { }).generate "config.yaml" {
                  app = {
                    telemetryEnabled = false;
                    storePath = "~/.local/share/docs-mcp-server";
                    embeddingModel = "openai:Qwen/Qwen3-Embedding-8B-TEE";
                  };
                  server = {
                    protocol = "http";
                    host = "127.0.0.1";
                    ports.default = 6280;
                  };
                  scraper = {
                    document.maxSize = 524288000; # 500MB for large PDFs
                    maxPages = 5000;
                    maxDepth = 10;
                    security = {
                      fileAccess = {
                        mode = "allowedRoots";
                        allowedRoots = [
                          "${config.home.homeDirectory}/repos"
                          "${config.home.homeDirectory}/Desktop"
                          "${config.home.homeDirectory}/Downloads"
                        ];
                      };
                    };
                  };
                  splitter = {
                    minChunkSize = 1000;
                    preferredChunkSize = 4000;
                    maxChunkSize = 10000;
                  };
                  search = {
                    overfetchFactor = 3;
                    vectorMultiplier = 15;
                  };
                  assembly = {
                    maxChunkDistance = 5;
                    maxParentChainDepth = 10;
                    childLimit = 5;
                    precedingSiblingsLimit = 3;
                    subsequentSiblingsLimit = 3;
                  };
                  embeddings = {
                    batchSize = 50;
                    requestTimeoutMs = 60000;
                    vectorDimension = 4096;
                  };
                };

                # Extracts only CHUTES_API_KEY_EMBEDDINGS from the shared secrets env,
                # maps it to OPENAI_API_KEY expected by docs-mcp-server
                docs-mcp-server-wrapper = pkgs.writeShellScriptBin "docs-mcp-server-wrapper" ''
                  export OPENAI_API_KEY="$(
                    ${pkgs.gnugrep}/bin/grep -oP '^CHUTES_API_KEY_EMBEDDINGS=\K.*' "${
                      config.age.secrets."llm_api_keys.env".path
                    }" 2>/dev/null
                  )"
                  exec ${pkgs.bun}/bin/bunx @arabold/docs-mcp-server@latest --protocol http --port 6280 --config "${docs-mcp-server-config}"
                '';
              in
              "${docs-mcp-server-wrapper}/bin/docs-mcp-server-wrapper";
            Environment = [
              # OpenAI-compatible SDK reads this; not a docs-mcp-server config key
              "OPENAI_API_BASE=https://chutes-qwen-qwen3-embedding-8b-tee.chutes.ai/v1"
              # Disable Playwright browser — we only index local files, no web scraping
              "PLAYWRIGHT_BROWSERS_PATH=0"
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

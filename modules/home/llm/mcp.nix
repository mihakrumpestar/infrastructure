# Docs MCP Server
{ inputs, ... }:
let
  secretsDir = inputs.infrastructure-secrets;
in
{
  home.llm-mcp = {
    homeManager =
      { config, pkgs, ... }:
      {
        age.secrets."llm_agent.env" = {
          file = "${secretsDir}/secrets/users/krumpy-miha/llm_agent.env.age";
          path = "${config.home.homeDirectory}/.agenix/secrets/llm_agent.env";
        };

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
                    embeddingModel = "embedding";
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
                    security.fileAccess = {
                      mode = "allowedRoots";
                      allowedRoots = [
                        "${config.home.homeDirectory}/repos"
                        "${config.home.homeDirectory}/Desktop"
                        "${config.home.homeDirectory}/Downloads"
                      ];
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

                # Extracts GATEWAY_API_KEY and GATEWAY_API_BASE from the shared secrets env,
                # maps them to OPENAI_API_KEY and OPENAI_API_BASE expected by docs-mcp-server
                wrapper = pkgs.writeShellScriptBin "docs-mcp-server-wrapper" ''
                  export OPENAI_API_KEY="$(
                    ${pkgs.gnugrep}/bin/grep -oP '^GATEWAY_API_KEY=\K.*' "${
                      config.age.secrets."llm_agent.env".path
                    }" 2>/dev/null
                  )"
                  export OPENAI_API_BASE="$(
                    ${pkgs.gnugrep}/bin/grep -oP '^GATEWAY_API_BASE=\K.*' "${
                      config.age.secrets."llm_agent.env".path
                    }" 2>/dev/null
                  )/v1"
                  exec ${pkgs.bun}/bin/bunx @arabold/docs-mcp-server@latest --protocol http --port 6280 --config "${docs-mcp-server-config}"
                '';
              in
              "${wrapper}/bin/docs-mcp-server-wrapper";
            Environment = [
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

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
      {
        config,
        pkgs,
        ...
      }:
      {
        age.secrets."llm_agent.env" = {
          file = "${secretsDir}/secrets/users/krumpy-miha/llm_agent.env.age";
          path = "${config.home.homeDirectory}/.agenix/secrets/llm_agent.env";
        };

        programs.opencode = {
          enable = true;

          # ~/.config/opencode/opencode.json
          settings = {
            autoupdate = false;
            default_agent = "plan";
            compaction.auto = false;

            # Provider configuration
            # Docs: https://opencode.ai/config.json
            # Models reference: https://models.dev/api.json
            # When looking to add a provider using the env, check the toml config in
            # https://github.com/anomalyco/models.dev/tree/dev/providers for the specific env var used
            provider = {
              Plexus = {
                npm = "@ai-sdk/openai-compatible";
                name = "Plexus";
                options = {
                  baseURL = "{env:GATEWAY_API_BASE}/v1";
                  apiKey = "{env:GATEWAY_API_KEY}";
                };
                models = {
                  default = {
                    name = "Plexus: default";
                    reasoning = true;
                    modalities = {
                      input = [
                        "text"
                        "image"
                      ];
                      output = [ "text" ];
                    };
                    limit = {
                      context = 1000000;
                      output = 132000;
                    };
                  };
                  testing = {
                    name = "Plexus: testing";
                    reasoning = true;
                    modalities = {
                      input = [
                        "text"
                        "image"
                      ];
                      output = [ "text" ];
                    };
                    limit = {
                      context = 1000000;
                      output = 132000;
                    };
                  };
                  experimental = {
                    name = "Plexus: experimental";
                    reasoning = true;
                    modalities = {
                      input = [
                        "text"
                        "image"
                      ];
                      output = [ "text" ];
                    };
                    limit = {
                      context = 1000000;
                      output = 132000;
                    };
                  };
                };
              };
            };

            # Use with: `use the <tool_name> tool`
            # Debug: opencode mcp list
            # Note: keep some disabled if not used as they add multiple 1000s tokens to context
            mcp = {
              # Gateway MCPs
              gateway-management = {
                type = "remote";
                url = "{env:GATEWAY_API_BASE}/mcp/plexus";
                enabled = false;
                headers.Authorization = "Bearer {env:GATEWAY_API_KEY}";
              };
              context7 = {
                type = "remote";
                url = "{env:GATEWAY_API_BASE}/mcp/context7";
                enabled = true;
                headers.Authorization = "Bearer {env:GATEWAY_API_KEY}";
              };
              exa = {
                type = "remote";
                url = "{env:GATEWAY_API_BASE}/mcp/exa";
                enabled = true;
                headers.Authorization = "Bearer {env:GATEWAY_API_KEY}";
              };
              "docs-mcp-server" = {
                type = "remote";
                url = "{env:GATEWAY_API_BASE}/mcp/docs-mcp-server";
                enabled = true;
                headers.Authorization = "Bearer {env:GATEWAY_API_KEY}";
              };

              # Local MCPs
              godoc = {
                type = "local";
                command = [
                  "go"
                  "run"
                  "github.com/mrjoshuak/godoc-mcp@latest"
                ];
                enabled = true;
                environment = {
                  CGO_ENABLED = "0";
                };
              };
              nixos = {
                type = "local";
                command = [
                  "nix"
                  "run"
                  "github:utensils/mcp-nixos"
                  "--"
                ];
                enabled = true;
              };
              "chrome-devtools" = {
                type = "local";
                command = [
                  "bunx"
                  "chrome-devtools-mcp@latest"
                  "--executable-path"
                  "${pkgs.ungoogled-chromium}/bin/chromium"
                ];
                enabled = true;
                environment = {
                  CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS = "true";
                };
              };

              # Not needed most of the time and/or add a lot to context
              # https://github.com/KeithCu/writeragent, maybe there are better ones?
              writeragent = {
                type = "remote";
                url = "http://localhost:8765/mcp";
                enabled = false;
              };
              "pdf-reader" = {
                type = "local";
                command = [
                  "bunx"
                  "@sylphx/pdf-reader-mcp"
                ];
                enabled = false;
              };
              xactions = {
                type = "local";
                command = [
                  "bunx"
                  "xactions-mcp"
                ];
                enabled = false;
                environment = {
                  XACTIONS_SESSION_COOKIE = "{env:XACTIONS_SESSION_COOKIE}";
                };
              };

              # Waiting for https://github.com/langflow-ai/openrag/issues/981#issuecomment-3947831540
              # openrag = {
              #   type = "local";
              #   command = [ "uvx" "openrag-mcp" ];
              #   enabled = true;
              #   environment = {
              #     OPENRAG_URL = "https://your-openrag-instance.com";
              #     OPENRAG_API_KEY = "orag_your_api_key_here";
              #   };
              # };
            };

            permission = {
              external_directory = {
                "/tmp/**" = "allow";
                "~/repos/**" = "allow";
                "~/go/**" = "allow";
                "/nix/store/**" = "allow";
              };
              edit = {
                "/tmp/**" = "allow";
                "~/repos/**" = "ask";
                "~/go/**" = "deny";
              };
            };

            tool_output = {
              max_lines = 5000;
              max_bytes = 1024000;
            };

            plugin = [
              "cc-safety-net"

              # /magic-compact — summarize all old assistant turns
              # /magic-compact 3 — keep the 3 most recent assistant turns, summarize the rest
              "magic-compact"
            ];
          };

          # ~/.config/opencode/AGENTS.md
          context = ''
            # General guidelines

            - Follow best coding practices: DRY, KISS, YAGNI principles.
            - Before making a change, scan landscape to indentify all places that need changes, and inform yourself with all the documentation we could possibly need.
            - Performance, readability, and maintainability are important.
            - If you do not understand something or something is strange, ask me or raise concern.
            - Never delete code comments, only if user explicitly requests it, and add them where needed/reasonable.
            - Do not do things blindly (assumptions kill): get the documentation, test the behaviour.
            - Take you time, quality over quantity.
            - Understand the problem as some things may not even be relevant and others might be missing.
            - Triple check your work.

            ## MCP tools

            Use tools:

            - `godoc`: for Go/Golang docs
            - `nixos`: Nix/NixOS docs
            - `context7`: any other docs
            - `exa` or `webset`: get search results or queary web
            - `chrome-devtools`: actually browse the web or website
            - `pdf-reader`: read PDF documents (DO NOT USE the build in "read" tool to read PDFs as it does not actually support them)
            - `docs-mcp-server`: whenever user tells you to use it
            - `writeragent`: MCP for LibreOffice suite
          '';

          # Web service (creates opencode-web.service)
          # Attach: opencode attach http://localhost:4096
          web = {
            enable = true;
            extraArgs = [
              "--hostname"
              "127.0.0.1"
              "--port"
              "4096"
            ];
          };
        };

        # Electron desktop client (CLI is installed by the HM module)
        home.packages = [ pkgs.opencode-desktop ];

        # Skills: mattpocock (remote) + local (inline)
        # Local skills override remote skills on name collision
        xdg.configFile = mattpocockSkillConfigs // {
          "opencode/skills/continue/SKILL.md".text = ''
            ---
            name: continue
            description: >
              Resume work after an interruption. Use when the conversation was cut off,
              the model stopped mid-response, or the user says "continue", "go on",
              "keep going", or invokes /continue.
            ---

            You were interrupted, please continue.
          '';

          "opencode/skills/evaluate/SKILL.md".text = ''
            ---
            name: evaluate
            description: >
              Give me an unbiased and unfiltered, and critical evaluation of the _.
              Use when user says "review", "evaluate", "critique", "roast", "critic",
              or invokes /review. Evaluates anything — code, ideas, architecture,
              documents, proposals, designs, tradeoffs.
            ---

            You are a ruthless, impartial critic. Your job is to give an **unbiased, unfiltered, and critical evaluation** of whatever the user provides.

            ## Principles

            - **No sugarcoating.** If something is bad, say so plainly.
            - **No false balance.** Don't invent positives just to soften the blow. Real positives only.
            - **No hedging.** Avoid "it depends" unless it genuinely depends on something the user should consider.
            - **No politeness filler.** Skip "great job!", "nice work!", "interesting approach". Get to the substance.
            - **Be specific.** Don't say "this could be improved". Say exactly what is wrong and why.
            - **Be concrete.** Cite specific lines, patterns, or decisions. No vague hand-waving.
            - **Prioritize by impact.** Lead with issues that cause real problems — bugs, security holes, perf hits, maintainability nightmares. Style nits go last or get omitted.
            - **Acknowledge tradeoffs explicitly.** If a design choice has real tradeoffs, lay them out honestly. Don't pretend one side is obviously right.
            - **Consider context.** A prototype and a production system deserve different levels of scrutiny. Adjust accordingly, but don't lower the bar — be clear about the gap.

            ## Output Format

            1. **Verdict** — One sentence: genuinely good, mixed, or bad. No hedging.
            2. **Critical issues** — Things that must be fixed. Ordered by severity.
            3. **Concerns** — Things that are likely problematic but debatable.
            4. **Strengths** — Real strengths only, if any exist. Omit this section if there are none.
            5. **Recommendations** — Concrete changes, in priority order. Not "consider X" — say "do X because Y".

            If the subject is good, say so in the verdict honestly — but still identify weaknesses, if there are any.
          '';

          "opencode/skills/spec/SKILL.md".text = ''
            ---
            name: spec
            description: >
              Write a detailed and comprehensive specification of the code that can be used
              to rewrite the module from scratch. Use when user says "spec", "specify",
              "specification", "spec it out", or invokes /spec.
            ---

            You are a specification writer. Analyze the given code thoroughly and produce a precise, exhaustive specification that captures every observable behavior — inputs, outputs, side effects, error handling, edge cases, dependencies, data structures, and configuration. The spec must be detailed enough that a competent developer could rewrite the module from scratch using only this document, with no access to the original source. Do not redesign or improve; spec what *is*. When something is genuinely ambiguous after careful reading, flag it explicitly.
          '';
        };

        # Service overrides for opencode-web
        systemd.user.services.opencode-web = {
          Unit = {
            After = [
              "graphical-session.target"
              "network-online.target"
            ];
            Wants = [ "network-online.target" ];
          };
          Service = {
            WorkingDirectory = "%h";
            TimeoutStartSec = 60;
            # Module doesn't set EnvironmentFile when web.environmentFile is null,
            # so we set it here with both the age secret and optional local secrets
            EnvironmentFile = [
              config.age.secrets."llm_agent.env".path
              "-/%h/.local/share/opencode/secrets.env"
            ];
          };
          Install = {
            WantedBy = [ "graphical-session.target" ];
          };
        };
      };
  };
}

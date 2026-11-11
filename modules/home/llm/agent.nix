# Other tested harneses:
# - https://github.com/monotykamary/deepseek-harness: too many tool call failures, not that Nix friendly for plugin management
#
# Many of them can be found at https://github.com/numtide/llm-agents.nix
{ inputs, ... }:
let
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

  # Upstream marks several skills user-invocable-only with
  # `disable-model-invocation: true`, which OpenCode maps to autoinvoke:false and
  # hides from the model. Strip it from every SKILL.md so the agent can start any
  # skill, for local and upstream skills alike.
  stripModelInvocationFlag =
    configs:
    builtins.mapAttrs (
      name: value:
      if builtins.match "opencode/skills/[^/]+/SKILL\\.md" name != null then
        {
          text =
            builtins.replaceStrings
              [ "disable-model-invocation: true\r\n" "disable-model-invocation: true\n" ]
              [ "" "" ]
              (builtins.readFile value.source);
        }
      else
        value
    ) configs;

  # In-repo skills (modules/home/llm/skills/<name>/*), same layout as upstream
  localSkillConfigs = discoverFiles "opencode/skills" ./skills;

  # cdp skill (browser-harness-js: SKILL.md + sdk/) from the upstream repo
  cdpSkillConfigs = discoverFiles "opencode/skills/cdp" inputs.browser-harness-js;

  # archify skill: interactive explorable diagrams (SKILL.md + bin/, schemas/,
  # examples/, references/, ...). The skill package lives in the repo's
  # archify/ subdirectory; node comes from the IDE home packages.
  archifySkillConfigs = discoverFiles "opencode/skills/archify" (inputs.archify + "/archify");

  # Every gateway model shares one shape; only the id (and display name) differ.
  gatewayModels = builtins.listToAttrs (
    map
      (id: {
        name = id;
        value = {
          name = "Gateway: ${id}";
          capabilities = {
            input = [
              "text"
              "image"
            ];
            output = [ "text" ];
            reasoning = {
              supported = true;
            };
          };
          limit = {
            context = 1000000;
            output = 132000;
          };
        };
      })
      [
        "default"
        "smart"
        "fast"
      ]
  );

  # Opencode plugin pins (single source of truth) for the v2 `plugins` config
  # key. hash = null -> exact npm spec (cached under ~/.cache/opencode/npm);
  # hash set -> hermetic store path. See lib/opencode-plugins (flake input).
  # Update: task update-opencode-plugins
  opencodePluginPins = {
    # Safety gate: blocks destructive commands and secret access
    cc-safety-net = {
      version = "2.7.2";
      hash = "sha256-SmIcmCp3EquCv6vr+lVdkF5pGlkfq0V64dIIk5oI6fE=";
    };

    # 7-agent orchestration suite (orchestrator, council, etc.)
    oh-my-opencode-slim = {
      version = "3.0.6";
      hash = null;
    };
  };
in
{
  home.llm-agent = {
    homeManager =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        anymd = pkgs.writeShellApplication {
          name = "anymd";
          runtimeInputs = [ pkgs.bun ];
          text = ''
            exec bunx @sylphx/anymd "$@"
          '';
        };

        # It is in nixpkgs, but out-of-date
        tokscale = pkgs.writeShellApplication {
          name = "tokscale";
          runtimeInputs = [ pkgs.bun ];
          text = ''
            exec bunx @tokscale/cli "$@"
          '';
        };
      in
      {
        options.my.llm.opencodeServerPassword = lib.mkOption {
          type = lib.types.str;
          default = "localhost";
          description = "Password for the loopback-only opencode v2 server (v2 serve always requires Basic auth).";
        };

        config = {
          # OpenCode is driven through OpenChamber (home.llm-ui), which themes
          # itself from its own settings.json, so the stylix opencode target
          # would only add an unused stylix theme plus a cli.json just to point
          # at it.
          stylix.targets.opencode.enable = false;

          programs.opencode = {
            enable = true;

            # ~/.config/opencode/opencode.json
            settings = {
              update = "disable";
              default_agent = "orchestrator";
              model = "gateway/default";
              websearch = false; # Using our own via MCP

              # Built-in compaction summarizes the older conversation and keeps a
              # recent verbatim tail. buffer reserves free tokens below the window,
              # so the 1M models compact at 450k instead of at the default
              # 1M - max(15%, 16k) = 850k. Models with a smaller window ignore the
              # buffer and fall back to the native reserve; compact those manually.
              compaction = {
                auto = true;
                keep.tokens = 24000;
                buffer = 550000;
              };

              # Provider configuration
              # Docs: https://opencode.ai/config.json
              # Models reference: https://models.dev/api.json
              # When looking to add a provider using the env, check the toml config in
              # https://github.com/anomalyco/models.dev/tree/dev/providers for the specific env var used
              providers.gateway = {
                name = "Gateway";
                package = "aisdk:@ai-sdk/openai-compatible";
                settings = {
                  baseURL = "{env:GATEWAY_API_BASE}/v1";
                  apiKey = "{env:GATEWAY_API_KEY}";
                  chunkTimeout = 60 * 1000;
                };
                models = gatewayModels;
              };

              # Use with: `use the <tool_name> tool`
              # Debug: opencode mcp list
              # Note: keep some disabled if not used as they add multiple 1000s tokens to context
              mcp.servers = {
                # Gateway MCPs
                gateway-management = {
                  type = "remote";
                  url = "{env:GATEWAY_API_BASE}/mcp/plexus";
                  headers."x-admin-key" = "{env:GATEWAY_ADMIN_KEY}";
                };
                context7 = {
                  type = "remote";
                  url = "{env:GATEWAY_API_BASE}/mcp/context7";
                  headers.Authorization = "Bearer {env:GATEWAY_API_KEY}";
                };
                keenable = {
                  type = "remote";
                  url = "{env:GATEWAY_API_BASE}/mcp/keenable";
                  headers.Authorization = "Bearer {env:GATEWAY_API_KEY}";
                };
                # Public remote MCP
                gh_grep = {
                  type = "remote";
                  url = "https://mcp.grep.app";
                };

                # X/Twitter reads: search, profiles, timelines, lists, communities.
                # The hosted MCP is OAuth-only (no static key), so it bypasses the
                # gateway and keeps its tokens in the OpenCode auth store.
                # One-time setup: `opencode mcp auth tweetapi`
                tweetapi = {
                  type = "remote";
                  url = "https://mcp.tweetapi.com/mcp";
                };

                # Local MCPs
                godoc = {
                  type = "local";
                  command = [
                    "${pkgs.go}/bin/go"
                    "run"
                    "github.com/mrjoshuak/godoc-mcp@latest"
                  ];
                  environment.CGO_ENABLED = "0";
                };
                nixos = {
                  type = "local";
                  command = [
                    "${pkgs.nix}/bin/nix"
                    "run"
                    "github:utensils/mcp-nixos"
                    "--"
                  ];
                };
                anymd = {
                  type = "local";
                  command = [ "${anymd}/bin/anymd" ];
                };
                # Code intelligence: per-project tree-sitter knowledge graph
                # (index in ~/.cache/codebase-memory-mcp; auto_index enforced by
                # the activation entry below). Query with search_graph/
                # trace_path/get_architecture instead of grep.
                "codebase-memory-mcp" = {
                  type = "local";
                  command = [ "${pkgs.codebase-memory-mcp}/bin/codebase-memory-mcp" ];
                };

                # Not needed most of the time and/or add a lot to context
                "docs-mcp-server" = {
                  type = "remote";
                  url = "http://127.0.0.1:6280/mcp";
                  disabled = true;
                };

                # Waiting for https://github.com/langflow-ai/openrag/issues/981#issuecomment-3947831540
                # Being implemented in https://github.com/langflow-ai/openrag/pull/2063
                # openrag = {
                #   type = "local";
                #   command = [ "uvx" "openrag-mcp" ];
                #   environment = {
                #     OPENRAG_URL = "https://your-openrag-instance.com";
                #     OPENRAG_API_KEY = "orag_your_api_key_here";
                #   };
                # };
              };

              # Ordered ruleset, last match wins
              permissions = [
                {
                  action = "external_directory";
                  resource = "/tmp/**";
                  effect = "allow";
                }
                {
                  action = "external_directory";
                  resource = "~/Projects/**";
                  effect = "allow";
                }
                {
                  action = "external_directory";
                  resource = "~/go/**";
                  effect = "allow";
                }
                {
                  action = "external_directory";
                  resource = "/nix/store/**";
                  effect = "allow";
                }
                {
                  action = "edit";
                  resource = "/tmp/**";
                  effect = "allow";
                }
                {
                  action = "edit";
                  resource = "~/Projects/**";
                  effect = "ask";
                }
                {
                  action = "edit";
                  resource = "~/go/**";
                  effect = "deny";
                }
              ];

              /*
                tool_output = {
                  max_lines = 5000;
                  max_bytes = 1024000;
                };
              */
              plugins = inputs.opencode-plugins.lib.entries {
                inherit pkgs;
                pins = opencodePluginPins;
              };
            };

            # ~/.config/opencode/AGENTS.md
            context = ./AGENTS.md;

            # Web service (creates opencode-web.service)
            # Attach: opencode --server http://localhost:4096
            web = {
              enable = true;
              # GATEWAY_API_KEY + GATEWAY_API_BASE for the service env
              environmentFile = config.age.secrets."llm_agent.env".path;
              extraArgs = [
                "--hostname"
                "127.0.0.1"
                "--port"
                "4096"
              ];
            };
          };

          systemd.user.services.opencode-web.Unit = {
            Wants = [ "agenix.service" ];
            After = [ "agenix.service" ];
          };

          # v2 serve always requires Basic auth; TUI/CLI get the password via
          # sessionVariables, the service needs it explicitly.
          systemd.user.services.opencode-web.Service.Environment = [
            "OPENCODE_SERVER_PASSWORD=${config.my.llm.opencodeServerPassword}"
          ];

          # codebase-memory-mcp keeps runtime settings in a SQLite DB, so HM
          # can't own them as a file; re-assert auto_index on every activation
          # (config set is idempotent; never fails activation).
          home.activation.codebaseMemoryMcpSettings =
            lib.hm.dag.entryAfter
              [
                "writeBoundary"
              ]
              ''
                ${pkgs.codebase-memory-mcp}/bin/codebase-memory-mcp config set auto_index true \
                  || echo "codebase-memory-mcp-settings: could not enable auto_index" >&2
              '';

          # Serve/CLI share this loopback password (Basic auth is always required).
          home.sessionVariables.OPENCODE_SERVER_PASSWORD = config.my.llm.opencodeServerPassword;

          home.packages = [
            # Document conversion CLI, same bunx package as the anymd MCP above.
            anymd

            # Token usage and cost tracker dashboard.
            tokscale

            # Code intelligence MCP server; on PATH for the CLI (index/config/
            # query). MCP entry lives in settings.mcp.servers above.
            pkgs.codebase-memory-mcp

            # Opencode plugin pin updater (lib/opencode-plugins)
            inputs.opencode-plugins.packages.${pkgs.stdenv.hostPlatform.system}.opencode-plugins-update

            (pkgs.writeShellApplication {
              name = "browser-harness-js";
              runtimeInputs = [
                pkgs.bun
                pkgs.curl
              ];
              text = ''
                exec "${inputs.browser-harness-js}/sdk/browser-harness-js" "$@"
              '';
              /*
                Usage:
                  browser-harness-js --status    # health: uptime, connected, sessionId
                  browser-harness-js --logs      # tail -f the REPL log
                  browser-harness-js --restart   # drop session state, fresh start
                  browser-harness-js --stop      # shut the REPL down
              */
            })
          ];

          # Skills: mattpocock (remote) + local (inline)
          # Local skills override remote skills on name collision
          xdg.configFile =
            stripModelInvocationFlag (
              mattpocockSkillConfigs // cdpSkillConfigs // archifySkillConfigs // localSkillConfigs
            )
            // {
              "opencode/oh-my-opencode-slim.jsonc".text = ''
                {
                  "$schema": "https://unpkg.com/oh-my-opencode-slim@latest/oh-my-opencode-slim.schema.json",
                  "preset": "gateway",
                  "autoUpdate": false,
                  // The plugin's built-in MCPs would overwrite the gateway-proxied MCPs 
                  // in OpenCode (plugin merges built-ins into the mcp config
                  "disabled_mcps": ["websearch", "gh_grep", "context7"],
                  "multiplexer": {
                    "type": "none"
                  },
                  "presets": {
                    "gateway": {
                      "orchestrator": {
                        "skills": ["*"],
                        "mcps": ["*"]
                      },
                      // Subagents follow the primary session model
                      "explorer": {
                        "inheritModelFrom": "session",
                        "skills": ["*"],
                        "mcps": ["*"]
                      },
                      "oracle": {
                        "inheritModelFrom": "session",
                        "skills": ["*"],
                        "mcps": ["*"]
                      },
                      "council": {
                        "inheritModelFrom": "session",
                        "skills": ["*"],
                        "mcps": ["*"]
                      },
                      "designer": {
                        "inheritModelFrom": "session",
                        "skills": ["*"],
                        "mcps": ["*"]
                      },
                      "fixer": {
                        "inheritModelFrom": "session",
                        "skills": ["*"],
                        "mcps": ["*"]
                      }
                    }
                  },
                  "council": {
                    "default_preset": "default",
                    "presets": {
                      "default": {
                        "alpha": {
                          "model": "gateway/default",
                          "prompt": "Focus on correctness, bugs, and edge cases."
                        },
                        "beta": {
                          "model": "gateway/default",
                          "prompt": "Focus on security, input validation, and data exposure."
                        },
                        "gamma": {
                          "model": "gateway/default",
                          "prompt": "Focus on performance, maintainability, and design."
                        }
                      }
                    }
                  }
                }
              '';

              # A one-line prompt with no discovery logic, so it belongs in the
              # command registry (/continue) rather than in the skill registry.
              "opencode/commands/continue.md".text = ''
                ---
                description: >
                  Resume work after an interruption. Use when the conversation was cut off,
                  the model stopped mid-response, or the user says "continue", "go on",
                  "keep going", or invokes /continue.
                ---

                You were interrupted, please continue.
              '';
            };
        };
      };
  };
}

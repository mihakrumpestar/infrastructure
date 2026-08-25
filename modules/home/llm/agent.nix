{ inputs, ... }:
let
  # ~/.dsh/AGENTS.md
  dshAgentsMd = ''
    # General guidelines

    - DO NOT use em dashes or other standalone dashes.
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

    Use tools (MCP tools are named `mcp__<server>__<tool>`):

    - `godoc`: for Go/Golang docs
    - `nixos`: Nix/NixOS docs
    - `context7`: any other docs
    - `exa` or `webset`: get search results or queary web
    - `pdf-reader`: read PDF documents (DO NOT USE the build in "read" tool to read PDFs as it does not actually support them)
    - `docs-mcp-server`: whenever user tells you to use it
    - `writeragent`: MCP for LibreOffice suite

    Browser automation: use the `cdp` skill (`browser-harness-js` CLI on PATH
    drives the user's Chrome via CDP; the REPL server auto-starts on first
    call and keeps one persistent session). User should start it with 
    `chromium --user-data-dir=/tmp/chrome-cdp --remote-debugging-port=9222`.
  '';

  # ~/.dsh/skills/continue/SKILL.md
  continueSkill = ''
    ---
    name: continue
    description: >
      Resume work after an interruption. Use when the conversation was cut off,
      the model stopped mid-response, or the user says "continue", "go on",
      "keep going", or invokes /continue.
    ---

    You were interrupted, please continue.
  '';

  # ~/.dsh/skills/evaluate/SKILL.md
  evaluateSkill = ''
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
in
{
  home.llm-agent = {
    homeManager =
      { config, pkgs, ... }:
      {
        age.secrets."llm_agent.env" = {
          file = "${inputs.infrastructure-secrets}/secrets/users/krumpy-miha/llm_agent.env.age";
          path = "${config.home.homeDirectory}/.agenix/secrets/llm_agent.env";
        };

        home.file = {
          ".dsh/AGENTS.md".text = dshAgentsMd;
          ".dsh/skills/continue/SKILL.md".text = continueSkill;
          ".dsh/skills/evaluate/SKILL.md".text = evaluateSkill;
          ".dsh/cordis.patch.yml".source = ./cordis.patch.yml;
          ".dsh/skills/cdp".source = inputs.browser-harness-js;
        };

        home.mutableFile.".dsh/settings.yaml".source = ./settings.yaml;

        # browser-harness-js CLI: thin wrapper so bun + curl resolve inside
        # the dsh service env; the script resolves its Bun REPL (repl.ts)
        # next to itself in the skill directory and auto-starts it on first
        # use. bun comes from nixpkgs, so the upstream bun self-installer
        # never triggers.
        home.packages = [
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

        # Web UI service URL: http://127.0.0.1:3080
        systemd.user.services.dsh = {
          Unit = {
            Description = "DeepSeek Harness (DSH) Web UI";
            Documentation = "https://github.com/mihakrumpestar/deepseek-harness";
            After = [
              "graphical-session.target"
              "network-online.target"
            ];
            Wants = [ "network-online.target" ];
          };
          Service = {
            Type = "simple";
            WorkingDirectory = "%h";
            TimeoutStartSec = 60;
            ExecStart = "${pkgs.nix}/bin/nix run github:mihakrumpestar/deepseek-harness/nix -- web --no-open --host 127.0.0.1 --port 3080";
            Environment = [
              # Settings reports Nix-owned updates instead of offering npm
              # self-update (see the upstream flake README).
              "DSH_INSTALL_CHANNEL=nix"
            ];
            # The age secret provides GATEWAY_API_KEY and GATEWAY_API_BASE
            # (used by the provider route and the gateway MCP proxies); the
            # optional local file can override or extend them.
            EnvironmentFile = [
              config.age.secrets."llm_agent.env".path
              "-/%h/.local/share/dsh/secrets.env"
            ];
            Restart = "on-failure";
            RestartSec = 10;
          };
          Install = {
            WantedBy = [ "graphical-session.target" ];
          };
        };
      };

    nixos = {
      my.impermanence.userDirectories = [ ".dsh" ];
    };
  };
}

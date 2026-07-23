{ inputs, ... }:
{
  home.llm-ui = {
    homeManager =
      {
        config,
        pkgs,
        lib,
        ...
      }:
      let
        source = inputs.openchamber.packages.${pkgs.stdenv.hostPlatform.system};
      in
      {
        services.openchamber = {
          enable = true;
          # Must override: the module's default (pkgs.callPackage ../pkgs/openchamber.nix {})
          # fails because nodeModules is a flake-internal FOD not available in nixpkgs
          package = source.openchamber;
          port = 4097;
          host = "127.0.0.1";

          # Point to the existing opencode serve instance managed by llm-agent
          opencode = {
            host = "http://127.0.0.1:4096";
            port = 4096;
            skipStart = true;
          };

          # ~/.config/openchamber/settings.json
          settings = {
            # Theme
            useSystemTheme = false;
            themeId = "vesper-dark";
            themeVariant = "dark";
            darkThemeId = "vesper-dark";

            # Defaults
            defaultModel = "Plexus/default";
            defaultAgent = "plan";
            defaultFileViewerPreview = false;

            # Chat UI
            chatRenderMode = "live";
            stickyUserHeader = false;
            collapsibleThinkingBlocks = false;
            wideChatLayoutEnabled = true;
            showSplitAssistantMessageActions = false;
            showReasoningTraces = true;
            usageDisplayMode = "usage";

            # Notifications
            nativeNotificationsEnabled = true;
            notifyOnCompletion = true;
            notifyOnSubtasks = true;
            notifyOnError = true;
            notifyOnQuestion = true;

            # Behavior
            inputSpellcheckEnabled = true;
            showDeletionDialog = true;
            autoDeleteEnabled = true;

            # Terminal
            terminalShell = "zsh";

            # Locale preferences
            weekStartPreference = "monday";
            timeFormatPreference = "24h";
          };
        };

        # Electron desktop client (alongside opencode-desktop from nixpkgs)
        home.packages = [
          source.openchamber
          source.openchamber-desktop
        ];

        # Ensure openchamber starts after the opencode service
        # Fix: the openchamber module puts `environment` at the top level of the
        # service, which generates an invalid [environment] section in the unit
        # file. Clear it and move the env vars to Service.Environment instead.
        # Fix: the openchamber CLI reads port from --port flag, not PORT env var.
        # Override ExecStart to pass --port explicitly.
        systemd.user.services.openchamber =
          let
            cfg = config.services.openchamber;
          in
          {
            environment = lib.mkForce { };

            Service = {
              ExecStart = lib.mkForce "${cfg.package}/bin/openchamber serve --foreground --port ${toString cfg.port}";
              Environment = [
                "OPENCHAMBER_DATA_DIR=${cfg.dataDir}"
                "OPENCHAMBER_HOST=${cfg.host}"
              ]
              ++ lib.optional (cfg.opencode.host != null) "OPENCODE_HOST=${cfg.opencode.host}"
              ++ lib.optional (cfg.opencode.port != null) "OPENCODE_PORT=${toString cfg.opencode.port}"
              ++ lib.optional cfg.opencode.skipStart "OPENCODE_SKIP_START=true";
            };

            Unit = {
              After = [
                "opencode.service"
                "network.target"
              ];
              Wants = [ "opencode.service" ];
            };
          };
      };
  };
}

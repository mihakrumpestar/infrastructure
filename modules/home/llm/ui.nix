/*
  # Alternatives:
  - https://github.com/getpaseo/paseo
*/
{ inputs, ... }:
{
  home.llm-ui = {
    homeManager =
      { pkgs, ... }:
      let
        source = inputs.openchamber.packages.${pkgs.stdenv.hostPlatform.system};

        # Wrap openchamber-desktop so it connects to the existing opencode
        # service instead of starting its own (which lacks GATEWAY_API_BASE).
        openchamber-desktop = pkgs.symlinkJoin {
          name = "openchamber-desktop-wrapped";
          paths = [ source.openchamber-desktop ];
          nativeBuildInputs = [ pkgs.makeWrapper ];
          postBuild = ''
            wrapProgram $out/bin/openchamber-desktop \
              --set OPENCODE_SKIP_START true \
              --set OPENCODE_HOST http://127.0.0.1:4096
          '';
        };

        # ~/.config/openchamber/settings.json
        settings = {
          # Theme
          useSystemTheme = false;
          themeId = "vesper-dark";
          themeVariant = "dark";
          darkThemeId = "vesper-dark";

          # Defaults
          defaultModel = "gateway/default";
          defaultAgent = "orchestrator";
          defaultFileViewerPreview = false;

          # Chat UI
          chatRenderMode = "live";
          stickyUserHeader = false;
          collapsibleThinkingBlocks = true;
          wideChatLayoutEnabled = true;
          showSplitAssistantMessageActions = false;
          showReasoningTraces = true;
          usageDisplayMode = "usage";

          # Notifications
          nativeNotificationsEnabled = true;
          notifyOnCompletion = true;
          notifyOnSubtasks = false;
          notifyOnError = false;
          notifyOnQuestion = true;
          showOpenCodeUpdateNotifications = false;

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
      in
      {
        # The openchamber flake no longer ships a home-manager service module,
        # so write the config file directly (same result the module produced).
        xdg.configFile."openchamber/settings.json".text = builtins.toJSON settings + "\n";

        # Electron desktop client (alongside opencode-desktop from nixpkgs)
        home.packages = [
          source.openchamber
          openchamber-desktop
        ];
      };
  };
}

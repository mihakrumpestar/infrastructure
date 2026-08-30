/*
  # Alternatives:
  - https://github.com/getpaseo/paseo
*/
{ inputs, ... }:
{
  home.llm-ui = {
    homeManager =
      { lib, pkgs, ... }:
      let
        source = inputs.openchamber.packages.${pkgs.stdenv.hostPlatform.system};

        # ~/.config/openchamber/settings.json. Re-asserted on each activation;
        # UI changes revert on the next switch.
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

          # Server
          desktopLocalPort = 4097;
        };

        settingsOverlay = pkgs.writeText "openchamber-settings-overlay.json" (
          builtins.toJSON settings + "\n"
        );

        # openchamber atomically rewrites settings.json (tmp+rename), mixing
        # preferences with runtime state (relay keys, projects, ...). HM can't
        # own it, the app's rename replaces managed symlinks. Instead, this
        # merges our prefs over the live file on each activation, leaving
        # runtime state untouched. Never fails activation.
        # https://github.com/openchamber/openchamber/issues/2182
        openchamber-settings-sync = pkgs.writeShellApplication {
          name = "openchamber-settings-sync";
          runtimeInputs = [
            pkgs.jq
            pkgs.coreutils
            pkgs.diffutils
          ];
          text = ''
            overlay="${settingsOverlay}"

            # Mirrors the app's own data dir resolution (XDG is not honored).
            data_dir="''${OPENCHAMBER_DATA_DIR:-$HOME/.config/openchamber}"
            settings_file="$data_dir/settings.json"

            install -d -m 700 "$data_dir"

            if [ ! -e "$settings_file" ]; then
              install -m 600 "$overlay" "$settings_file"
              exit 0
            fi

            if ! jq empty "$settings_file" >/dev/null 2>&1; then
              mv "$settings_file" "$settings_file.corrupt"
              install -m 600 "$overlay" "$settings_file"
              exit 0
            fi

            tmp="$(mktemp "$data_dir/settings.json.sync.XXXXXX")"
            if ! jq --slurpfile prefs "$overlay" '. * $prefs[0]' "$settings_file" > "$tmp"; then
              echo "openchamber-settings-sync: merge failed, leaving $settings_file unchanged" >&2
              rm -f "$tmp"
              exit 0
            fi

            if ! cmp -s "$tmp" "$settings_file"; then
              chmod 600 "$tmp"
              mv "$tmp" "$settings_file"
            else
              rm -f "$tmp"
            fi
          '';
        };

        # Connect to the existing opencode service instead of starting its own.
        # OpenChamber runs `git ls-remote` per remote on startup (active-branch
        # check), triggering SSH key prompts. Fail SSH fast and silently
        # instead; local git ops still work. Override per-launch with
        # GIT_SSH_COMMAND=ssh.
        openchamber-desktop-local = pkgs.symlinkJoin {
          name = "openchamber-desktop-local-wrapped";
          paths = [ source.openchamber-desktop ];
          nativeBuildInputs = [ pkgs.makeWrapper ];
          postBuild = ''
            wrapProgram $out/bin/openchamber-desktop \
              --set-default OPENCODE_SKIP_START true \
              --set-default OPENCODE_HOST http://127.0.0.1:4096 \
              --set-default GIT_SSH_COMMAND "ssh -o BatchMode=yes -o IdentityAgent=none -o ConnectTimeout=1"
          '';
        };
      in
      {
        home.activation.openchamberSettings = lib.hm.dag.entryAfter [
          "writeBoundary"
        ] "${openchamber-settings-sync}/bin/openchamber-settings-sync";

        home.packages = [
          source.openchamber
          openchamber-desktop-local
        ];
      };
  };
}

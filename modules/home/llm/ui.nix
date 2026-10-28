/*
  # Alternatives:
  - https://github.com/getpaseo/paseo
*/
{ inputs, ... }:
{
  home.llm-ui = {
    homeManager =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        source = inputs.openchamber.packages.${pkgs.stdenv.hostPlatform.system};

        # The app's own settings registry: one source of truth for which key
        # lives where, so nothing here needs a hand-kept second list. A key the
        # registry does not know fails the eval instead of landing in the wrong
        # file, where the app would drop it without a word.
        registry = builtins.fromJSON (
          builtins.readFile "${inputs.openchamber}/packages/web/server/lib/opencode/settings-registry.json"
        );

        # Only two files exist, so any other scope has no home; a dropped key
        # would look applied and never be read.
        scopeOf =
          name:
          let
            scope = (registry.fields.${name} or { }).scope or null;
          in
          if
            builtins.elem scope [
              "instance"
              "profile"
            ]
          then
            scope
          else
            throw "openchamber: settings key '${name}' is missing or not instance/profile scoped";

        # Re-asserted on each activation; UI changes revert on the next switch.
        settings = {
          # Theme
          useSystemTheme = false;
          themeId = "mono-plus-dark";
          themeVariant = "dark";
          darkThemeId = "mono-plus-dark";

          # Defaults
          defaultModel = "gateway/default";
          defaultAgent = "orchestrator";
          defaultFileViewerPreview = false;
          desktopMinimizeToTrayEnabled = true;

          # Chat UI
          chatRenderMode = "live";
          stickyUserHeader = false;
          collapsibleThinkingBlocks = true;
          wideChatLayoutEnabled = true;
          showSplitAssistantMessageActions = false;
          showReasoningTraces = true;
          expandReasoningWhileStreaming = true;
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

        # The app keeps instance facts in settings.json and the profile in
        # preferences.json, which wins where both have a key. Split by the
        # registry's scope so each lands where it is read.
        byScope = lib.groupBy scopeOf (builtins.attrNames settings);
        overlayFor =
          scope:
          pkgs.writeText "openchamber-settings-${scope}-overlay.json" (
            builtins.toJSON (lib.getAttrs (byScope.${scope} or [ ]) settings) + "\n"
          );
        instanceOverlay = overlayFor "instance";
        profileOverlay = overlayFor "profile";

        # The app rewrites both files (tmp+rename) with our prefs mixed into
        # runtime state, so HM can't own them: the rename replaces symlinks.
        # Merge our prefs over the live files on each activation instead.
        # https://github.com/openchamber/openchamber/issues/2182
        openchamber-settings-sync = pkgs.writeShellApplication {
          name = "openchamber-settings-sync";
          runtimeInputs = [
            pkgs.jq
            pkgs.coreutils
            pkgs.diffutils
          ];
          text = ''
            instanceOverlay="${instanceOverlay}"
            profileOverlay="${profileOverlay}"

            data_dir="''${OPENCHAMBER_DATA_DIR:-$HOME/.config/openchamber}"
            settings="$data_dir/settings.json"
            prefs="$data_dir/preferences.json"

            install -d -m 700 "$data_dir"

            # Move src over dst at mode 600, only when the content changed.
            commit() {
              if cmp -s "$1" "$2"; then
                rm -f "$1"
              else
                chmod 600 "$1"
                mv "$1" "$2"
              fi
            }

            # Never fail activation: leave the file as it was and move on.
            bail() {
              echo "openchamber-settings-sync: $1, leaving it unchanged" >&2
              rm -f "$2"
              exit 0
            }

            # Instance facts: our prefs over the app's runtime state. A file we
            # cannot parse is moved aside rather than truncated: it still holds
            # projects and window bounds worth keeping.
            if [ -s "$settings" ] && ! jq -e . "$settings" >/dev/null 2>&1; then
              mv "$settings" "$settings.corrupt"
            fi
            [ -s "$settings" ] || echo '{}' > "$settings"

            jq --slurpfile o "$instanceOverlay" '. * $o[0]' "$settings" > "$settings.new" \
              || bail "could not merge $settings" "$settings.new"
            commit "$settings.new" "$settings"

            # Profile: each key as { value, updatedAt }. An unchanged value keeps
            # its stamp. A file we cannot parse is left alone: the app pauses
            # profile writes on it, so replacing it would drop unreadable state.
            if [ -s "$prefs" ] && ! jq -e '
                type == "object" and .version == 1 and (.fields | type) == "object"
              ' "$prefs" >/dev/null 2>&1
            then
              echo "openchamber-settings-sync: $prefs is not a version-1 document, leaving it unchanged" >&2
              exit 0
            fi
            [ -s "$prefs" ] || echo '{"version":1,"fields":{}}' > "$prefs"

            jq --slurpfile o "$profileOverlay" --argjson now "$(date +%s%3N)" '
              .fields |= reduce ($o[0] | to_entries[]) as $e (.;
                .[$e.key] = (if .[$e.key].value == $e.value
                              then .[$e.key]
                              else { value: $e.value, updatedAt: $now } end))
            ' "$prefs" > "$prefs.new" || bail "could not merge $prefs" "$prefs.new"
            commit "$prefs.new" "$prefs"
          '';
        };

        # Connect to the existing opencode service instead of starting its own.
        # v2 serve always requires Basic auth, so the wrapper supplies the
        # loopback password (openchamber captures it once at startup).
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
              --set-default OPENCODE_SERVER_PASSWORD ${config.my.llm.opencodeServerPassword} \
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

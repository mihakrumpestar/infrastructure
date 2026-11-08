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
          # Theme. themeVariant is a derived key: the VS Code settings panel
          # drops it when it writes, so a theme change there shows the system
          # theme until the next activation re-asserts it. It still pins the
          # first launch of a fresh home, which is why it stays managed.
          useSystemTheme = false;
          themeId = "github-dark";
          themeVariant = "dark";
          darkThemeId = "github-dark";
          lightThemeId = "github-light";

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

          # Composer
          largeTextPasteBehavior = "inline-double-paste";
          allowPromptingSubagentSessions = true;
          savePastedImagesAsFiles = true;

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

          # Permissions: a new session accepts a tool request unless the safety
          # net (Jev) says the user should decide. Existing sessions keep the
          # mode they were given; the shield in the composer changes one.
          permissionDefaultMode = "safety";

          # Terminal
          terminalShell = "zsh";

          # Locale preferences
          weekStartPreference = "monday";
          timeFormatPreference = "24h";

          # Voice
          dictationEnabled = true;
          dictationAutoSend = true;
          sttProvider = "local";
          sttLocalModel = "parakeet-tdt-0.6b-v3-int8";

          # Server
          desktopLocalPort = 4097;
        };

        # The Jev classifier answers on Plexus' System One endpoint with the
        # gateway key, so the pick is a file pair in the data dir, not a
        # setting: classification.json names the source, classifier-endpoint.json
        # holds the URL, model and key (the app's own shape and mode). The app
        # rereads both on every use, so a rewrite applies without a restart.
        # A user unit after agenix, which is what decrypts the key.
        openchamber-classifier = pkgs.writeShellApplication {
          name = "openchamber-classifier";
          runtimeInputs = [
            pkgs.jq
            pkgs.coreutils
            pkgs.diffutils
          ];
          text = ''
            # No secret, no endpoint: the app then holds every permission
            # request, which is the safe side, so this is a warning, not a
            # failed unit on a host where decryption did not run.
            if [ -z "''${GATEWAY_API_BASE:-}" ] || [ -z "''${GATEWAY_API_KEY:-}" ]; then
              echo "openchamber-classifier: GATEWAY_API_BASE/GATEWAY_API_KEY are unset, leaving the classifier unconfigured" >&2
              exit 0
            fi

            data_dir="''${OPENCHAMBER_DATA_DIR:-$HOME/.config/openchamber}"
            source="$data_dir/classification.json"
            endpoint="$data_dir/classifier-endpoint.json"

            # Create only: an existing directory keeps its mode and ACLs.
            [ -d "$data_dir" ] || install -d -m 700 "$data_dir"

            # Write only on change, so a login does not touch the mtimes.
            commit() {
              if cmp -s "$1" "$2"; then
                rm -f "$1"
              else
                chmod "$3" "$1"
                mv "$1" "$2"
              fi
            }

            jq -n '{version: 1, source: "custom"}' > "$source.new"
            commit "$source.new" "$source" 600

            # No trailing slash on the base, so the path is appended once.
            jq -n \
              --arg url "''${GATEWAY_API_BASE%/}/v1/decisions" \
              --arg model "decision" \
              --arg key "$GATEWAY_API_KEY" \
              '{version: 1, endpoint: {url: $url, model: $model, key: $key}}' > "$endpoint.new"
            commit "$endpoint.new" "$endpoint" 600
          '';
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

            # Create only: an existing directory keeps its mode and ACLs.
            [ -d "$data_dir" ] || install -d -m 700 "$data_dir"

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

            # Profile: each key as { value, updatedAt }. A managed key is
            # replaced whole, dropping any per-surface overrides, so the NixOS
            # value is what every surface reads; an unchanged value keeps its
            # stamp. A file we cannot parse is left alone: the app pauses
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
                (if (.[$e.key] | type) == "object" then .[$e.key] else {} end) as $prev
                | .[$e.key] = {
                    value: $e.value,
                    updatedAt: (if $prev.value == $e.value then ($prev.updatedAt // $now) else $now end),
                  })
            ' "$prefs" > "$prefs.new" || bail "could not merge $prefs" "$prefs.new"
            commit "$prefs.new" "$prefs"
          '';
        };

        # sherpa-onnx-node (local dictation) links libstdc++ from the compiler
        # toolchain. Electron and bun do not put it on the dynamic loader path,
        # so the addon's dlopen fails and dictation reports the addon missing.
        sherpaLibPath = "${pkgs.stdenv.cc.cc.lib}/lib";

        openchamber-local = pkgs.symlinkJoin {
          name = "openchamber-local-wrapped";
          paths = [ source.openchamber ];
          nativeBuildInputs = [ pkgs.makeWrapper ];
          postBuild = ''
            wrapProgram $out/bin/openchamber \
              --prefix LD_LIBRARY_PATH : ${sherpaLibPath}
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
              --prefix LD_LIBRARY_PATH : ${sherpaLibPath} \
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

        # A user unit after agenix, which decrypts the key; PartOf makes a
        # secret rotation restart it too. The optional EnvironmentFile keeps a
        # host without the secret from ending up with a failed unit: the
        # script reports it and the app holds every request instead.
        systemd.user.services.openchamber-classifier = {
          Unit = {
            Description = "Point OpenChamber's Jev classifier at Plexus";
            After = [ "agenix.service" ];
            Requires = [ "agenix.service" ];
            PartOf = [ "agenix.service" ];
          };
          Service = {
            Type = "oneshot";
            EnvironmentFile = "-${config.age.secrets."llm_agent.env".path}";
            UMask = "0077";
            ExecStart = "${openchamber-classifier}/bin/openchamber-classifier";
          };
          Install.WantedBy = [ "default.target" ];
        };

        home.packages = [
          openchamber-local
          openchamber-desktop-local
        ];
      };
  };
}

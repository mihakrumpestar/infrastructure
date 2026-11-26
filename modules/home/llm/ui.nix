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
        cfg = config.my.llm;
        host = cfg.opencodeServerHost;
        urlHost = if lib.hasInfix ":" host then "[${host}]" else host;
        opencodeUrl = "http://${urlHost}:${toString cfg.opencodeServerPort}";
        source = inputs.openchamber.packages.${pkgs.stdenv.hostPlatform.system};

        settings = {
          useSystemTheme = false;
          themeId = "github-dark";
          themeVariant = "dark";
          darkThemeId = "github-dark";
          lightThemeId = "github-light";

          defaultModel = config.programs.opencode.settings.model;
          defaultAgent = config.programs.opencode.settings.default_agent;
          defaultFileViewerPreview = false;
          desktopMinimizeToTrayEnabled = true;

          chatRenderMode = "live";
          stickyUserHeader = false;
          collapsibleThinkingBlocks = true;
          wideChatLayoutEnabled = true;
          showSplitAssistantMessageActions = false;
          showReasoningTraces = true;
          expandReasoningWhileStreaming = true;
          usageDisplayMode = "usage";

          # Keep project context on the flat list and use OpenChamber's In work shelf.
          sidebarGrouping = "time";
          sidebarDetailedZoneRows = true;
          sidebarKeepPinnedInPlace = false;
          sidebarShowWorkSection = true;

          largeTextPasteBehavior = "inline-double-paste";
          allowPromptingSubagentSessions = true;
          savePastedImagesAsFiles = true;

          nativeNotificationsEnabled = true;
          notifyOnCompletion = true;
          notifyOnSubtasks = false;
          notifyOnError = false;
          notifyOnQuestion = true;
          showOpenCodeUpdateNotifications = false;

          inputSpellcheckEnabled = true;
          showDeletionDialog = true;
          autoDeleteEnabled = false;
          permissionDefaultMode = "safety";
          terminalShell = "zsh";
          weekStartPreference = "monday";
          timeFormatPreference = "24h";

          dictationEnabled = true;
          dictationAutoSend = true;
          sttProvider = "local";
          sttLocalModel = "parakeet-tdt-0.6b-v3-int8";
          desktopLocalPort = 4097;
        };

        # The app ignores fields in the wrong file. Split using the pinned registry.
        registry = builtins.fromJSON (
          builtins.readFile "${inputs.openchamber}/packages/web/server/lib/settings/settings-registry.json"
        );
        scopeOf =
          name:
          let
            scope = (registry.fields.${name} or { }).scope or null;
          in
          if scope == "instance" || scope == "profile" then
            scope
          else
            throw "openchamber: settings key '${name}' is not instance/profile scoped";
        byScope = lib.groupBy scopeOf (builtins.attrNames settings);
        overlayFor =
          scope:
          pkgs.writeText "openchamber-settings-${scope}-overlay.json" (
            builtins.toJSON (lib.getAttrs (byScope.${scope} or [ ]) settings) + "\n"
          );

        # OpenChamber writes these files itself, so merge the managed keys
        # rather than replacing its projects, windows, and other preferences.
        openchamberSettingsSync = pkgs.writeShellApplication {
          name = "openchamber-settings-sync";
          runtimeInputs = [
            pkgs.jq
            pkgs.coreutils
            pkgs.diffutils
          ];
          text = ''
            umask 077
            data_dir="''${OPENCHAMBER_DATA_DIR:-$HOME/.config/openchamber}"
            mkdir -p -- "$data_dir"
            now="$(date +%s%3N)"

            merge() {
              local scope="$1" file="$2" overlay="$3" initial="$4" tmp
              tmp="$(mktemp "$data_dir/.settings-sync.XXXXXX")"
              if ! {
                if [ -e "$file" ] || [ -L "$file" ]; then
                  cat -- "$file"
                else
                  printf '%s\n' "$initial"
                fi
              } | jq -es --arg scope "$scope" --slurpfile o "$overlay" --argjson now "$now" '
                if length == 1 and (.[0] | type) == "object" then .[0]
                else error("expected one settings object") end
                | if $scope == "instance" then . * $o[0]
                  elif .version != 1 or (.fields | type) != "object" then
                    error("expected a version-1 preferences document")
                  else
                    .fields |= reduce ($o[0] | to_entries[]) as $e (.;
                      (if (.[$e.key] | type) == "object" then .[$e.key] else {} end) as $prev
                      | .[$e.key] = {
                          value: $e.value,
                          updatedAt: (if $prev.value == $e.value then ($prev.updatedAt // $now) else $now end),
                        })
                  end
              ' > "$tmp" 2>/dev/null; then
                echo "openchamber-settings-sync: could not merge $file, leaving it unchanged" >&2
                rm -f -- "$tmp"
              elif cmp -s -- "$tmp" "$file"; then
                rm -f -- "$tmp"
              else
                mv -fT -- "$tmp" "$file"
              fi
            }

            merge instance "$data_dir/settings.json" "${overlayFor "instance"}" '{}'
            merge profile "$data_dir/preferences.json" "${overlayFor "profile"}" '{"version":1,"fields":{}}'
          '';
        };

        # The desktop's dictation addon needs this at dlopen time.
        sherpaLibPath = "${pkgs.stdenv.cc.cc.lib}/lib";
        openchamber = pkgs.symlinkJoin {
          name = "openchamber-local-wrapped";
          paths = [ source.openchamber ];
          nativeBuildInputs = [ pkgs.makeWrapper ];
          postBuild = ''
            wrapProgram "$out/bin/openchamber" \
              --prefix LD_LIBRARY_PATH : ${sherpaLibPath}
          '';
        };
        openchamberDesktop = pkgs.symlinkJoin {
          name = "openchamber-desktop-local-wrapped";
          paths = [ source.openchamber-desktop ];
          nativeBuildInputs = [ pkgs.makeWrapper ];
          # Do not start a second OpenCode or prompt for SSH keys during background git checks.
          postBuild = ''
            wrapProgram "$out/bin/openchamber-desktop" \
              --prefix LD_LIBRARY_PATH : ${sherpaLibPath} \
              --set-default OPENCODE_SKIP_START true \
              --set-default OPENCODE_HOST ${lib.escapeShellArg opencodeUrl} \
              --set-default OPENCODE_SERVER_PASSWORD ${lib.escapeShellArg cfg.opencodeServerPassword} \
              --set-default GIT_SSH_COMMAND "ssh -o BatchMode=yes -o IdentityAgent=none -o ConnectTimeout=1"
          '';
        };

        # Link the SOPS-rendered endpoint without copying its key into app data.
        openchamberClassifier = pkgs.writeShellApplication {
          name = "openchamber-classifier";
          runtimeInputs = [
            pkgs.jq
            pkgs.coreutils
            pkgs.diffutils
          ];
          text = ''
            umask 077
            data_dir="''${OPENCHAMBER_DATA_DIR:-$HOME/.config/openchamber}"
            mkdir -p -- "$data_dir"
            endpoint_file="''${OPENCHAMBER_DREX_ENDPOINT_FILE:-}"

            link_drex() {
              local target="$data_dir/classifier-endpoint.json"
              jq -es 'length == 1 and (.[0] |
                .version == 1 and
                (.endpoint.key | type == "string" and length <= 4000 and test("^nace_sk_[^[:space:]]+$"))
              )' "$endpoint_file" >/dev/null 2>&1 || return 1
              if [ "$(readlink -- "$target" 2>/dev/null || true)" != "$endpoint_file" ]; then
                ln -sfnT --backup=numbered -- "$endpoint_file" "$target"
              fi
            }

            source=off
            if [ -n "$endpoint_file" ]; then
              if link_drex; then
                source=custom
              else
                echo "openchamber-classifier: cannot load Drex credentials; leaving the classifier off" >&2
              fi
            fi

            tmp="$(mktemp "$data_dir/.classifier.XXXXXX")"
            trap 'rm -f -- "$tmp"' EXIT
            jq -n --arg source "$source" '{version: 1, source: $source}' > "$tmp"
            if ! cmp -s -- "$tmp" "$data_dir/classification.json"; then
              mv -fT -- "$tmp" "$data_dir/classification.json"
            fi
          '';
        };
      in
      {
        home.packages = [
          openchamber
          openchamberDesktop
        ];

        home.activation.openchamberSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run ${openchamberSettingsSync}/bin/openchamber-settings-sync
        '';

        systemd.user.services.openchamber-classifier = {
          Unit = {
            Description = "Configure OpenChamber's permission classifier";
          }
          // lib.optionalAttrs cfg.openchamberDrex.enable {
            After = [ "sops-nix.service" ];
            Wants = [ "sops-nix.service" ];
            PartOf = [ "sops-nix.service" ];
          };
          Service = {
            Type = "oneshot";
            RemainAfterExit = true;
            Environment = [
              "OPENCHAMBER_DREX_ENDPOINT_FILE=${
                if cfg.openchamberDrex.enable then
                  config.sops.templates."openchamber-drex-endpoint.json".path
                else
                  ""
              }"
            ];
            UMask = "0077";
            ExecStart = "${openchamberClassifier}/bin/openchamber-classifier";
          };
          Install.WantedBy = [ "default.target" ];
        };
      };
  };
}

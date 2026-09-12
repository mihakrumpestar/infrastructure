{ ... }:
{
  home.note-taking =
    let
      targetDir = "knowledge-base";
    in
    {
      homeManager =
        { pkgs, lib, ... }:
        let
          # TaskNotes takes `customStatuses` wholesale (built-ins must be
          # repeated), cannot persist UI edits (read-only data.json, see the
          # communityPlugins comment), and matches statuses by `value`.
          humanize =
            id:
            let
              spaced = lib.strings.replaceStrings [ "-" ] [ " " ] id;
            in
            lib.strings.toUpper (lib.substring 0 1 spaced) + lib.substring 1 (-1) spaced;

          mkStatus =
            {
              id,
              value ? id,
              label ? humanize id,
              color,
              isCompleted ? false,
              excludeFromCycle ? false,
              autoArchive ? false,
              autoArchiveDelay ? 5,
            }:
            {
              inherit
                id
                value
                label
                color
                isCompleted
                excludeFromCycle
                autoArchive
                autoArchiveDelay
                ;
            };

          mkMarker =
            { id, color }:
            mkStatus {
              inherit id color;
              excludeFromCycle = true;
            };

          taskStatuses = lib.imap0 (i: status: status // { order = i; }) (
            # Built-in statuses (must match the plugin's defaults).
            [
              (mkStatus {
                id = "none";
                color = "#cccccc";
              })
              (mkStatus {
                id = "open";
                color = "#808080";
              })
              (mkStatus {
                id = "in-progress";
                color = "#0066cc";
              })
              (mkStatus {
                id = "done";
                color = "#00aa00";
                isCompleted = true;
              })
            ]
            ++ [
              (mkMarker {
                id = "recurring";
                color = "#6366f1";
              })
              (mkMarker {
                id = "celebration"; # Birthdays and name days (god).
                color = "#f59e0b";
              })
            ]
          );
        in
        {
          programs.obsidian = {
            enable = true;

            cli.enable = true;

            vaults.notes.target = targetDir;

            defaultSettings = {
              appearance = {
                accentColor = "#ffffff";
              };

              themes = with pkgs.obsidianThemes; [
                material-ocean
              ];

              corePlugins = [
                #"audio-recorder"
                #"backlink"
                "bases"
                #"bookmarks"
                #"canvas"
                "command-palette"
                #"daily-notes"
                "editor-status"
                "file-explorer"
                #"file-recovery"
                #"footnotes"
                "global-search"
                #"graph"
                #"markdown-importer"
                #"note-composer"
                #"outgoing-link"
                #"outline"
                #"page-preview"
                #"properties"
                #"publish"
                #"random-note"
                "slash-command"
                #"slides"
                #"switcher"
                #"sync"
                #"tag-pane"
                "templates"
                #"webviewer"
                "word-count"
                #"workspaces"
                #"zk-prefixer"
              ];

              # Plugins with `settings` get a read-only, store-symlinked data.json.
              # Plugins that persist a "seen" marker into it (changelog, starter note)
              # would otherwise show those on every start, since they cannot save the
              # marker themselves - so such markers are pinned to the installed
              # plugin version below.
              communityPlugins = with pkgs.obsidianPlugins; [
                obsidian-excalidraw-plugin
                fit
                sfb-open-in-new-tab
                {
                  pkg = git-file-explorer;
                  settings = {
                    # The sync widget runs `git fetch` on every refresh for
                    # ahead/behind counts, which triggers SSH key prompts.
                    gitSyncWidgetActive = false;
                  };
                }
                table-editor-obsidian
                {
                  pkg = tasknotes;
                  settings = {
                    moveArchivedTasks = true;
                    archiveFolder = "TaskNotes/Archive";
                    taskCreationDefaults.defaultScheduledDate = "none"; # Don't pre-set the "scheduled" field on new tasks.
                    calendarViewSettings.locale = "en-GB"; # day/month/year
                    customStatuses = taskStatuses;
                    starterNoteCreated = true;
                    lastSeenVersion = tasknotes.version;
                  };
                }
                {
                  pkg = enhance-navigate-pane;
                  settings = {
                    iconSet = "lucide";
                  };
                }
                {
                  pkg = obsidian-languagetool-plugin;
                  settings = {
                    pickyMode = true;
                    englishVeriety = "en-US";
                  };
                }
                {
                  pkg = termy; # lean-terminal does not work with NixOS
                  settings = {
                    fontFamily = "'Droid Sans Mono', monospace, 'MesloLGS NF'";
                    scrollback = 5000;
                    platformShells = {
                      windows = "cmd";
                      darwin = "zsh";
                      linux = "zsh";
                    };
                    lastSeenChangelogVersion = termy.version;
                  };
                }
              ];
            };
          };

          # The stylix obsidian target injects a "Stylix Config.css" snippet into vaults
          stylix.targets.obsidian.enable = false;
        };

      nixos = {
        my.impermanence.userDirectories = [
          targetDir
        ];
      };
    };
}

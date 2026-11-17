{ inputs, ... }:
let
  languageToolServer =
    (import "${inputs.infrastructure-secrets}/secrets/data.nix").krumpy-miha.languagetool_server;
in
{
  home.note-taking =
    let
      targetDir = "knowledge-base";
    in
    {
      homeManager =
        { pkgs, ... }:
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
                # Snapshot store behind Time Machine's version history; also
                # what obsidian-version-history-diff reads. Device local.
                "file-recovery"
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
                nextcloud-sync
                time-machine
                obsidian-version-history-diff
                {
                  pkg = enhance-navigate-pane;
                  settings = {
                    iconSet = "lucide";
                  };
                }
                {
                  pkg = obsidian-languagetool-plugin;
                  settings = {
                    serverUrl = languageToolServer;
                    urlMode = "custom";
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

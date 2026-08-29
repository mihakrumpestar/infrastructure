{ ... }:
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
                obsidian-material-ocean
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

              communityPlugins = with pkgs.obsidianPlugins; [
                obsidian-excalidraw-plugin
                fit
                tasknotes
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

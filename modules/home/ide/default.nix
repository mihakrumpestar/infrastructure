{ ... }:
{
  home.ide = {
    homeManager =
      { config, pkgs, ... }:
      let
        vscode-ltex-plus-offline = pkgs.vscode-utils.buildVscodeMarketplaceExtension rec {
          mktplcRef = {
            name = "vscode-ltex-plus";
            version = "15.6.1";
            publisher = "ltex-plus";
          };
          vsix = builtins.fetchurl {
            url = "https://github.com/ltex-plus/vscode-ltex-plus/releases/download/${mktplcRef.version}/vscode-ltex-plus-${mktplcRef.version}-offline-linux-x64.vsix";
            sha256 = "09jp99vcafj83d4s5p8d9f2k2znv96ig9awhr4mdn4qnx8081qdy";
          };
        };
        # Unofficial patches:
        # - oauth-linux: official builds gate protocol-URL handling behind
        #   __WIN32__, so OAuth callbacks are dropped on Linux
        # - keyring-adoption: adopt accounts from the system keychain on
        #   fresh machines (zero-click sign-in across PCs sharing a keyring)
        # - disable-background-fetch: gate all automatic fetches behind
        #   GITHUB_DESKTOP_DISABLE_BACKGROUND_FETCH (set by the wrapper below)
        github-desktop-patched = pkgs.github-desktop.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [
            ./github-desktop-oauth-linux.patch
            ./github-desktop-keyring-adoption.patch
            ./github-desktop-disable-background-fetch.patch
          ];
        });

        # Stop automatic background fetches without touching the session
        # environment; override per-launch with
        # GITHUB_DESKTOP_DISABLE_BACKGROUND_FETCH=0.
        github-desktop-local = pkgs.symlinkJoin {
          name = "github-desktop-local-wrapped";
          paths = [ github-desktop-patched ];
          nativeBuildInputs = [ pkgs.makeWrapper ];
          postBuild = ''
            wrapProgram $out/bin/github-desktop \
              --set-default GITHUB_DESKTOP_DISABLE_BACKGROUND_FETCH 1
          '';
        };
      in
      {
        # This are ment for system, not projects
        home.packages = with pkgs; [
          # Latex
          tex-fmt
          texliveFull # Containes pdflatex and Tex packages required by xournalpp (full is the minimum req to run)
          python313Packages.pygments # For Latex code snippets

          # Typst
          typst

          # Python
          python3
          uv

          # Nix
          nixd # Language server
          nixfmt # Formatter

          # Javascript
          bun
          nodejs

          # Markdown
          mermaid-cli

          # Git
          git
          git-filter-repo
          github-cli
          github-desktop-local

          yaak # TODO: test
          scc
          bruno
          devbox
        ];

        home.sessionVariables = {
          CGO_ENABLED = "0"; # Disable use of CGO

          # Disable Github CLI telemetry
          GH_TELEMETRY = "false";
          DO_NOT_TRACK = "true";
        };

        # For uv, go, etc. installables
        home.sessionPath = [
          "${config.home.homeDirectory}/.local/bin"
        ];

        # devenv: per-project dev environments; the zsh integration activates
        # them on cd and the VS Code extension mirrors the env into the editor.
        programs.devenv = {
          enable = true;
          enableZshIntegration = true;
        };

        xdg.configFile."secretspec/config.toml".text = ''
          [defaults]
          provider = "keyring"
          profile = "default"
        '';

        programs.vscodium = {
          enable = true;
          mutableExtensionsDir = false;
          profiles.default = {
            extensions =
              with pkgs.open-vsx;
              [
                # find them on https://open-vsx.org/ # or "vscode-marketplace"
                # (note that all characters have to be converted to lower case if they are not already)
                #
                # General
                activitywatch.aw-watcher-vscode
                vscode-icons-team.vscode-icons
                donjayamanne.githistory
                edwinhuish.better-comments-next
                waderyan.gitblame
                github.github-vscode-theme
                hediet.vscode-drawio
                jeanp413.open-remote-ssh
                matthewpi.caddyfile-support
                pomdtr.excalidraw-editor
                redhat.vscode-yaml
                ritwickdey.liveserver
                #streetsidesoftware.code-spell-checker
                tamasfe.even-better-toml
                tumido.cron-explained
                mathematic.vscode-pdf # VSCode does not have native PDF support for some reason

                # Latex
                james-yu.latex-workshop

                # Go
                golang.go
                joelhill.go-template # Go template syntax for *.yaml.gotmpl and *.yml.gotmpl

                # Python
                detachhead.basedpyright
                charliermarsh.ruff
                ms-python.python # Required by Ruff

                # Docker
                docker.docker
                ms-azuretools.vscode-docker
                exiasr.hadolint

                # Nix
                jnoortheen.nix-ide
                #kamadorueda.alejandra

                # devenv: mirror the devenv environment into the editor and terminals
                datakurre.devenv

                # MD
                shd101wyy.markdown-preview-enhanced
                yzhang.markdown-all-in-one
                davidanson.vscode-markdownlint

                # MDX
                unifiedjs.vscode-mdx

                # Typst
                myriad-dreamin.tinymist

                # HTML/VSS/JS/TS
                bradlc.vscode-tailwindcss
                dbaeumer.vscode-eslint
                ecmel.vscode-html-css
                esbenp.prettier-vscode
                astro-build.astro-vscode

                # AI
                fedaykindev.openchamber # openchamber.apiUrl

                # Rest
                #humao.rest-client

                # HCL
                hashicorp.hcl
              ]
              ++ [
                vscode-ltex-plus-offline # https://ltex-plus.github.io/ltex-plus/advanced-usage.html
              ];

            # Enable these 2 to prevent homeManager's userSettings from being written
            enableUpdateCheck = true;
            enableExtensionUpdateCheck = true;
          };

          # userSettings = lib.importJSON ./settings.json; # Using home.mutableFile instead
        };

        stylix.targets.vscode.enable = false; # We are using the one from extension

        home.mutableFile = {
          # code --diff users/krumpy-miha/home/ide/settings.json ~/.config/VSCodium/User/settings.json
          ".config/VSCodium/User/settings.json".source = ./vscode-settings.jsonc;
          ".vscode-oss/argv.json".source = ./vscode-argv.jsonc;
        };

        # Switch GitHub CLI authentication profile via secret-service
        programs.zsh.initContent = ''
          gh-auth() {
            if [[ $# -eq 0 ]]; then
              echo "Usage: gh-auth <profile>"
              return 1
            fi
            local profile="$1"
            local secret_name="gh-cli-''${profile}"
            local token
            token=$(secret-tool lookup UserName "$secret_name" 2>/dev/null) || true
            if [[ -z "$token" ]]; then
              echo "Error: Secret '$secret_name' not found in secret-service" >&2
              return 1
            fi
            export GH_TOKEN="$token"
            export GITHUB_TOKEN="$token"
            echo "GH_TOKEN and GITHUB_TOKEN set for profile '$profile'"
          }
        '';
      };
  };
}

{
  config,
  pkgs,
  ...
}: let
  store-secrets = config.my.store-secrets.secrets;
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
in {
  home.packages = with pkgs; [
    # Task runner
    go-task

    # Github
    gh

    # Formatters
    prettier
    #nixfmt-rfc-style # Not using anymore since it hangs too much
    alejandra # For Nix
    caddy # Also a linter

    # Latex
    tex-fmt
    texlive.combined.scheme-full # Containes pdflatex and Tex packages required by xournalpp (full is the minimum req to run)
    python313Packages.pygments # For Latex code snippets

    # Typst
    typst

    # Python
    python3
    basedpyright
    uv

    # Nix
    nil
    tix # Does not appear to work yet as IDE LSP

    # Quarto
    quarto

    # Dockerfile
    hadolint

    # Golang
    go
    # Next pkgs are for the extension
    gopls
    delve # dlv
    impl
    gotests
    go-tools # staticcheck
    golangci-lint

    # Javascript
    bun
    nodejs
  ];

  programs.vscode = {
    enable = true;
    package = pkgs.vscodium.override {
      commandLineArgs = "--password-store=gnome-libsecret";
    };
    mutableExtensionsDir = false;
    profiles.default = {
      extensions = with pkgs.open-vsx;
        [
          # find them on https://open-vsx.org/ # or "vscode-marketplace"
          # General
          activitywatch.aw-watcher-vscode
          vscode-icons-team.vscode-icons
          donjayamanne.githistory
          edwinhuish.better-comments-next
          eliostruyf.screendown
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

          # Latex
          james-yu.latex-workshop

          # Go
          golang.go

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
          kamadorueda.alejandra

          # MDQ
          quarto.quarto

          # MD
          yzhang.markdown-all-in-one
          davidanson.vscode-markdownlint
          shd101wyy.markdown-preview-enhanced # Does not support Alerts: https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#alerts

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

          # AI (using it as web only now)
          #sst-dev.opencode

          # Rest
          humao.rest-client

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
    ".config/VSCodium/User/settings.json".source =
      pkgs.replaceVars
      ./vscode-settings.jsonc {
        inherit (store-secrets) languagetool_server;
      };
  };

  home.sessionVariables = {
    CGO_ENABLED = "0"; # Disable use of CGO
  };

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
      export GH_TOKEN="$token"      # Used by github cli
      export GITHUB_TOKEN="$token"  # Used by git-cliff cli
      echo "GH_TOKEN and GITHUB_TOKEN set for profile '$profile'"
    }
  '';
}

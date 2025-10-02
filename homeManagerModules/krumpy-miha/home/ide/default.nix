{
  config,
  pkgs,
  ...
}: let
  vscode-ltex-plus-offline = pkgs.vscode-utils.buildVscodeMarketplaceExtension rec {
    mktplcRef = {
      name = "vscode-ltex-plus";
      version = "15.5.1";
      publisher = "ltex-plus";
    };
    vsix = builtins.fetchurl {
      name = "${mktplcRef.publisher}-${mktplcRef.name}.zip";
      url = "https://github.com/ltex-plus/vscode-ltex-plus/releases/download/${mktplcRef.version}/vscode-ltex-plus-${mktplcRef.version}-offline-linux-x64.vsix";
      sha256 = "19mq89qlzzyyih83jsq50szxsg3ghc1h7vrmh3s26nmc3r4lwjfz";
    };
  };
in {
  home.packages = with pkgs; [
    # Formatters
    nodePackages.prettier
    #nixfmt-rfc-style # Not using anymore since it hangs too much
    alejandra # For Nix
    caddy # Also a linter

    # Latex
    tex-fmt
    texlive.combined.scheme-full # Containes pdflatex and Tex packages required by xournalpp (full is the minimum req to run)
    python313Packages.pygments

    # Python
    python3
    basedpyright

    # LSP (language server)
    # nixd # Before
    nil

    # Quarto
    quarto

    # Dockerfile
    hadolint

    # Golang
    go
    # Next pkgs are for the extension
    gccgo
    gopls
    delve # dlv
    #vscgo
    #goplay
    impl
    gotests
    go-tools # staticcheck

    golangci-lint

    # KCL
    kcl
    #kcl-language-server # TODO: report compile errors
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
          # shd101wyy.markdown-preview-enhanced # Does not support Alerts: https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#alerts
          bierner.markdown-preview-github-styles

          # MDX
          unifiedjs.vscode-mdx

          # HTML/VSS/JS/TS
          bradlc.vscode-tailwindcss
          dbaeumer.vscode-eslint
          ecmel.vscode-html-css
          esbenp.prettier-vscode
          astro-build.astro-vscode

          # AI
          #saoudrizwan.claude-dev
          #kilocode.kilo-code
          saoudrizwan.claude-dev # Cline

          # Rest
          humao.rest-client

          # HCL
          hashicorp.hcl

          # Dot (Graphviz)
          tintinweb.graphviz-interactive-preview
        ]
        ++ [
          pkgs.vscode-marketplace.casualjim.gotemplate
          pkgs.vscode-marketplace.jinliming2.vscode-go-template
          pkgs.vscode-marketplace.karyan40024.gotmpl-syntax-highlighter
          pkgs.vscode-marketplace.romantomjak.go-template

          # KCL
          pkgs.vscode-marketplace.kcl.kcl-vscode-extension # The one in VSIX is not latest

          vscode-ltex-plus-offline # https://ltex-plus.github.io/ltex-plus/advanced-usage.html
        ];

      # Enable these 2 to prevent userSettings from being written
      enableUpdateCheck = true;
      enableExtensionUpdateCheck = true;
    };

    # userSettings = lib.importJSON ./settings.json; # Using my.home.mutableFile instead
  };

  stylix.targets.vscode.enable = false;

  # code --diff users/krumpy-miha/home/ide/settings.json ~/.config/VSCodium/User/settings.json
  my.home.mutableFile.".config/VSCodium/User/settings.json".source =
    pkgs.replaceVars
    ./settings.json {
      inherit (config.my.store-secrets.secrets) languagetool_server;
    };

  # npx does not work properly for some reason
  my.home.mutableFile.".config/VSCodium/User/globalStorage/kilocode.kilo-code/settings/mcp_settings.json".text = ''
    {
      "mcpServers": {
        "context7": {
          "command": "${pkgs.bun}/bin/bunx",
          "args": ["-y", "@upstash/context7-mcp"],
          "env": {
            "DEFAULT_MINIMUM_TOKENS": "6000"
          }
        }
      }
    }
  '';
}

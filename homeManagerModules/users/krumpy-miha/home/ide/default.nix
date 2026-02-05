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
    # LLM
    opencode

    # Formatters
    nodePackages.prettier
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

    # LSP (language server)
    # Nix
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
          # shd101wyy.markdown-preview-enhanced # Does not support Alerts: https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#alerts
          bierner.markdown-preview-github-styles

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
          sst-dev.opencode # Used kilocode.kilo-code, but they shifted focus to their CLI fork of Opencode

          # Rest
          humao.rest-client

          # HCL
          hashicorp.hcl
        ]
        ++ [
          vscode-ltex-plus-offline # https://ltex-plus.github.io/ltex-plus/advanced-usage.html
        ];

      # Enable these 2 to prevent homeMnagaer's userSettings from being written
      enableUpdateCheck = true;
      enableExtensionUpdateCheck = true;
    };

    # userSettings = lib.importJSON ./settings.json; # Using my.home.mutableFile instead
  };

  stylix.targets.vscode.enable = false; # We are using the one from extension

  my.home.mutableFile = {
    # code --diff users/krumpy-miha/home/ide/settings.json ~/.config/VSCodium/User/settings.json
    ".config/VSCodium/User/settings.json".source =
      pkgs.replaceVars
      ./settings.json {
        inherit (store-secrets) languagetool_server;
      };

    ".config/opencode/opencode.json".source = ./opencode.jsonc;

    # opencode agent list
    ".config/opencode/AGENTS.md".source = ./AGENTS.md;
  };

  systemd.user.services.opencode = {
    Unit = {
      Description = "Opencode AI Assistant";
      After = [
        "graphical-session.target"
      ];
    };

    Service = {
      Type = "simple";
      TimeoutStartSec = 60;
      ExecStart = "${pkgs.opencode}/bin/opencode web --hostname 127.0.0.1 --port 4096";
      Environment = "OPENCODE_CONFIG=${./opencode.jsonc}";

      Restart = "on-failure";
      RestartSec = 5;
    };

    Install = {
      WantedBy = ["default.target"];
    };
  };
}

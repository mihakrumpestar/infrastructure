{
  lib,
  pkgs,
  ...
}: {
  # Fonts
  fonts.packages = with pkgs; [
    meslo-lgs-nf # font for starship
    SDL2_ttf
    carlito
    dejavu_fonts
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    font-awesome
    hack-font
    liberation_ttf
    roboto
    roboto-mono
    ubuntu-classic
    fira-code
    fira-code-symbols
    mplus-outline-fonts.githubRelease
    dina-font
    proggyfonts
    font-adobe-75dpi
    font-adobe-100dpi
  ];

  nixpkgs.config.permittedInsecurePackages = [
    "python3.13-ecdsa-0.19.1"
  ];

  programs.starship = {
    enable = true;
    settings = {
      # from https://github.com/ChrisTitusTech/mybash/blob/main/starship.toml with some modifications

      format = lib.concatStrings [
        "[](#3B4252)"
        "$username"
        "$hostname"
        "$battery"
        "[](bg:#434C5E fg:#3B4252)"
        "$directory"
        "[](fg:#434C5E bg:#4C566A)"
        "$git_branch"
        "$git_status"
        "[](fg:#4C566A bg:#86BBD8)"
        "$golang"
        "$java"
        "$nodejs"
        "$rust"
        "[](fg:#86BBD8 bg:#06969A)"
        "$nix_shell"
        "$docker_context"
        "[](fg:#06969A bg:#33658A)"
        "$time"
        "[ ](fg:#33658A)"
        "\n"
        "$cmd_duration"
        "$character"
      ];

      command_timeout = 500;
      add_newline = true;

      username = {
        show_always = true;
        style_user = "bg:#3B4252";
        style_root = "fg:red bg:#3B4252";
        format = "[$user ]($style)";
      };

      hostname = {
        style = "bg:#3B4252";
        ssh_symbol = "🌐";
        format = "[$ssh_symbol](bold fg:#33ccff $style)[$hostname ]($style)";
        trim_at = "";
      };

      directory = {
        style = "bg:#434C5E";
        format = "[ $path ]($style)";
        truncation_length = 8;
        truncation_symbol = "…/";
        substitutions = {
          "Documents" = " ";
          "Downloads" = " ";
          "Music" = " ";
          "Pictures" = " ";
        };
      };

      # Git

      git_branch = {
        symbol = "";
        style = "bg:#4C566A";
        format = "[ $symbol $branch ]($style)";
      };

      git_status = {
        style = "bold bg:#4C566A";
        format = "[$all_status$ahead_behind ]($style)";
      };

      # Language

      golang = {
        symbol = "";
        style = "bg:#86BBD8 fg:black";
        format = "[ $symbol ($version) ]($style)";
      };

      java = {
        symbol = "";
        style = "bg:#86BBD8 fg:black";
        format = "[ $symbol ($version) ]($style)";
      };

      nodejs = {
        symbol = "";
        style = "bg:#86BBD8 fg:black";
        format = "[ $symbol ($version) ]($style)";
      };

      rust = {
        symbol = "";
        style = "bg:#86BBD8 fg:black";
        format = "[ $symbol ($version) ]($style)";
      };

      # Shells

      docker_context = {
        symbol = "";
        style = "bg:#06969A";
        format = "[ $symbol $context $path]($style)";
      };

      nix_shell = {
        impure_msg = "";
        pure_msg = "";
        style = "bg:#06969A";
        format = "[ $symbol$state(\($name\)) ]($style)";
      };

      # Miscelnous

      time = {
        disabled = false;
        time_format = "%R";
        style = "bg:#33658A";
        format = "[ $time ]($style)";
      };

      cmd_duration = {
        min_time = 500;
        format = "[$duration]($style) ";
      };
    };
  };

  environment.etc."fastfetch/config.jsonc".source = ./fastfetch_config.jsonc;

  # CLI only
  environment.systemPackages = with pkgs; [
    git
    wget
    curl
    nano
    btop
    lsof
    killall
    bat # Better cat
    less
    tree
    zoxide # Better cd
    eza # Better ls
    ncdu # Disk usage

    trash-cli # Command line trashcan (recycle bin) interface
    speedtest-go # Internet speedtest in CLI
    rclone
    rsync
    gh
    fastfetch # New Neofetch
    onefetch # Neofetch/fastfetch for Git
    ipfetch # Neofetch for IPs
    iperf

    # Disks
    parted
    e2fsprogs # mkfs
    xfsprogs # mkfs.xfs

    # TUI: Terminal-UI
    lazygit # Git terminal UI
    lazydocker # Docker container management, Portainer alternative
    lazyjournal

    # Archiving
    gnutar # tar
    p7zip
    unzip
    zip # Zip files

    # Development tools
    devbox # Only one that supports zsh, "nix develop" does not
    #devenv # Pollutes project root with too many files, currently it does not support zsh: https://github.com/cachix/devenv/issues/36
  ];

  # Default shell
  users.defaultUserShell = pkgs.zsh;

  programs = {
    fzf.fuzzyCompletion = true; # Command-line fuzzy finder/search
    yazi.enable = true; # Terminal file manager
    pay-respects.enable = true;
    nix-index.enable = true;

    zsh = {
      enable = true;
      histSize = 10000;
      autosuggestions.enable = true;
      syntaxHighlighting.enable = true;
      # https://zsh.sourceforge.io/Doc/Release/Options.html
      setOptions = [
        "NO_BEEP"
        "EXTENDED_HISTORY"
        "HIST_IGNORE_DUPS"
        "HIST_FIND_NO_DUPS"
        "HIST_IGNORE_SPACE"
        "HIST_SAVE_NO_DUPS"
        "SHARE_HISTORY"
      ];
      interactiveShellInit = ''
        export HIST_STAMPS="yyyy/mm/dd"

        # Set the default editor
        export EDITOR='codium --wait'
        export DIFFTOOL="codium --wait --diff $LOCAL $REMOTE"
        export VISUAL='codium'

        ### Bindkeys ###

        # Test: showkey -a

        # Accept suggestion controls
        bindkey '^[[1;5C' forward-word           # Ctrl + Right (accept up to next word)
        bindkey '^[[1;5F' autosuggest-accept     # Ctrl + End (accept entire suggestion)
        bindkey '^ ' autosuggest-accept          # Ctrl + Space (accept entire suggestion)
        bindkey '^F' forward-char                # Ctrl + F (accept one character)
        bindkey '^[[Z' autosuggest-execute       # Shift + Tab (execute suggestion)

        ### Stats ###

        if [[ -z "$IN_NIX_SHELL" ]]; then
          fastfetch

          if [[ -d ".git" ]]; then
            onefetch --no-color-palette
          fi
        fi

        ### Subshell ###

        if [[ -f "devbox.json" && -z "$IN_NIX_SHELL" ]]; then
          devbox shell
        fi
      '';
      shellAliases = {
        # # Basic
        cp = "cp -i";
        mv = "mv -i";
        rm = "trash -v";
        mkdir = "mkdir -p";
        ps = "ps auxf";
        less = "less -R";
        cls = "clear";
        grep = "grep --color=auto";
        df = "df -h";
        free = "free -mt";
        wget = "wget -c";

        # Grep
        h = "history | grep"; # Search command line history
        p = "ps aux | grep"; # Search running processes
        f = "find . | grep"; # Search files in the current folder

        # Show open ports
        openports = "netstat -nape --inet";

        # Alias's for safe and forced reboots
        reboot-safe = "sudo shutdown -r now";
        reboot-force = "sudo shutdown -r -n now";

        # Alias's to show disk space and space used in a folder
        diskspace = "du -S | sort -n -r |more";
        folders = "du -h --max-depth=1";
        folderssort = "find . -maxdepth 1 -type d -print0 | xargs -0 du -sk | sort -rn";
        tree = "tree -CAhF --dirsfirst";
        treed = "tree -CAFd";
        mountedinfo = "df -hT";

        # # Personal
        code = "codium";
      };
      ohMyZsh = {
        enable = true;
        plugins = [
          "colored-man-pages"
          "colorize"
          "emoji"
          "extract"
          "eza"
          "gh"
          "git-commit" # https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/git-commit
          "gitfast"
          "git-lfs"
          "golang"
          "history-substring-search"
          "npm"
          "pip"
          "podman"
          "safe-paste"
          "ssh"
          "sudo"
          "systemd"
          "tldr"
          "vscode"
          "yarn"
          "z"
          "zoxide"
          "zsh-interactive-cd"
          "zsh-navigation-tools"
        ];
      };
    };
  };
}

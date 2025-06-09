{
  lib,
  pkgs,
  ...
}: {
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
        impure_msg = "📦 devbox";
        style = "bg:#06969A";
        format = "[ $state ]($style)";
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
    devbox
  ];

  # Default shell
  users.defaultUserShell = pkgs.zsh;

  programs = {
    fzf.fuzzyCompletion = true; # Command-line fuzzy finder/search
    yazi.enable = true; # Terminal file manager
    pay-respects.enable = true;
    command-not-found.enable = true;

    zsh = {
      enable = true;
      histSize = 10000;
      #extended = true;
      #expireDuplicatesFirst = true;
      #historySubstringSearch.enable = true;
      #autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      interactiveShellInit = ''
        # Terminal
        setopt NO_BEEP # Never beep
        export HIST_STAMPS="yyyy/mm/dd"

        # Set the default editor
        export EDITOR='codium --wait'
        export DIFFTOOL="codium --wait --diff $LOCAL $REMOTE"
        export VISUAL='codium'

        # Other
        export DEVBOX_NO_PROMPT=true

        eval "$(pay-respects zsh --alias)"

        ### Bindkeys ###

        # Test: showkey -a

        # Accept suggestion controls
        bindkey '^[[1;5C' forward-word           # Ctrl + Right (accept up to next word)
        bindkey '^[[1;5F' autosuggest-accept     # Ctrl + End (accept entire suggestion)
        bindkey '^ ' autosuggest-accept          # Ctrl + Space (accept entire suggestion)
        bindkey '^F' forward-char                # Ctrl + F (accept one character)
        bindkey '^[[Z' autosuggest-execute       # Shift + Tab (execute suggestion)

        ### Subshell ###

        if [[ -f "devbox.json" && -z "$DEVBOX_SHELL_ENABLED" ]]; then
          devbox shell
        fi

        ### Stats ###

        fastfetch

        if [[ -d ".git" && "$PWD" != "$HOME" ]]; then
          onefetch --no-color-palette
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
      /*
      envExtra = ''
        restart-kde() {
            killall plasmashell && kstart5 plasmashell &
        }

        # Searches for text in all files in the current folder
        ftext() {
            # -i case-insensitive
            # -I ignore binary files
            # -H causes filename to be printed
            # -r recursive search
            # -n causes line number to be printed
            # optional: -F treat search term as a literal, not a regular expression
            # optional: -l only print filenames and not the matching lines ex. grep -irl "\$1" *
            grep -iIHrn --color=always "$1" . | less -r
        }
      '';
      */
      ohMyZsh = {
        enable = true;
        plugins = [
          "colored-man-pages"
          "colorize"
          "command-not-found"
          "docker"
          "docker-compose"
          "emoji"
          "extract"
          "eza"
          "fzf"
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

{pkgs, ...}: {
  # Default shell
  users.defaultUserShell = pkgs.zsh;

  home-manager.sharedModules = [
    {
      # Has to be enabled since we need at least the basic zsh config file in users home dir
      programs.zsh.enable = true;
    }
  ];

  programs.zsh = {
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
}

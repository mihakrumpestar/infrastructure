{pkgs, ...}: {
  home.packages = with pkgs; [
    # Terminal
    #kitty # Terminal emulator
    zellij # Modern Tmux (terminal multiplexer)
    pciutils # Computer utility info
    usbutils # USB utility info
    udisks2 # CMD: udisksctl
    udiskie # A user-level daemon for auto-mounting
    mesa-demos # Check GPU drivers
    drill
    dig
    cloc
    man

    kdePackages.yakuake # Drop down terminal emulator

    # Video/Audio and photo
    audacity # Sound
    vlc # Media Player
    handbrake
    obs-studio
    # No color picker currently works properly on KDE6 (use the self created script command `color-picker`)
    gimp # Alternative is: https://github.com/PintaProject/Pinta
    inkscape
    upscayl # Image upscaler
    kdePackages.gwenview # Image viewer
    curtail # Image compress
    gradia # Make screenshots presentable for the web

    # Apps
    rnote # Draving software, prev: xournalpp
    kdePackages.kate # General GUI text editor
    evince # Document viewer (PDF)
    #zoom-us # UNFREE license
    freetube # Youtube client
    #drawio # Drawing tool # UNFREE license
    kdePackages.kcalc # Calculator
    #freecad-wayland # 3D design tool # TODO: broken

    # AI
    #jan # Has hardcoded providers and endpoints
    cherry-studio # AI chat app, app list https://github.com/billmei/every-chatgpt-gui
    #gpt4all # TODO: does not compile
    chatbox

    # Office Suite
    libreoffice-fresh
    #onlyoffice-bin

    # File Management
    #xfce.thunar # Settings don't get saved, too basic
    #nautilus # Too basic
    nemo-with-extensions
    kdePackages.okular # PDF viewer
    kdePackages.ark # GUI to compress or uncompress data
    p7zip # Req for above
    unrar # Req for above
    peazip # GUI archiving tool
    file-roller # GUI archiving tool
    nextcloud-client

    # Programming
    git
    git-filter-repo
    gnumake # make
    bruno
    yaak # TODO: test
    gitleaks # Check for leaks in git repos, scans all branches with all commit history
    devbox
    devtoolbox # Development tools at your fingertips

    # Tools
    gsmartcontrol
    gnome-disk-utility
    # error: Package ‘ventoy-1.1.05’ in "" is marked as insecure, refusing to evaluate.
    # NIXPKGS_ALLOW_INSECURE=1 NIXPKGS_ALLOW_UNFREE=1 nix-shell -p ventoy-full-qt --run ventoy-gui
    android-tools # adb
    scrcpy # adb # Check Window Options in Developer Settings
    # scrcpy --video-codec=h265 --stay-awake --max-fps=60
    # scrcpy --video-codec=h265 --stay-awake --max-fps=60 --new-display=1200x2600/120
    qtscrcpy # adb
    universal-android-debloater # CLI: uad-ng
    mission-center # System monitoring GUI
    filezilla
    droidcam # Webcam emulator from Android
    #flameshot # alt: satty       // Screenshot tool
    rymdport # Wormhole client
    cpu-x # CPU-Z alternative
    qbittorrent-enhanced
    remmina
    moonlight-qt
    ffmpeg
    #rustdesk # Always has to be compiled

    # Printer and scanner
    #simple-scan # Scanning (Gnome)

    /*
    Might use in the future:

    https://github.com/Sathvik-Rao/ClipCascade
    */
  ];

  /*
  Core-dumps continuesly # TODO: find replacement
  services.flameshot = {
  enable = true;
  settings = {
    General = {
      copyOnDoubleClick = true;
      copyPathAfterSave = true;
      predefinedColorPaletteLarge = true;
      saveLastRegion = true;
      showHelp = false;
      showStartupLaunchMessage = false;
      startupLaunch = true;
      uiColor = "#dea9ed";
      undoLimit = 100;
      disabledTrayIcon = true;
      userColors = "picker, #800000, #ff0000, #ffff00, #00ff00, #008000, #00ffff, #0000ff, #ff00ff, #800080, #ffffff, #000000";
    };
  };
  };
  */

  # fuzzel: application launcher and fuzzy finder
  # TODO: make automatic Command+Space shortcut to open it
  programs.fuzzel = {
    enable = true;
    # man fuzzel.ini
    settings = {
      main = {
        match-mode = "fuzzy";
        anchor = "center";

        fields = "name,generic,comment,categories,filename,keywords";
        #font = "Hack:weight=bold:size=36";
        line-height = 40;
        width = 45;
        show-actions = true;
      };

      border = {
        radius = 20;
      };
    };
  };

  services.activitywatch = {
    enable = true;
    watchers = {
      aw-watcher-afk = {
        package = pkgs.activitywatch;
      };
    };
  };

  # For activitywatch
  systemd.user.services.awatcher = {
    Unit = {
      Description = "AWatcher";
      After = ["graphical-session.target"];
    };

    Service = {
      Type = "simple";
      TimeoutStartSec = 120;
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 10"; # The important part
      ExecStart = "${pkgs.awatcher}/bin/awatcher";

      Restart = "always";
      RestartSec = 5;
      RestartSteps = 2;
      RestartMaxDelaySec = 15;
    };

    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };
}

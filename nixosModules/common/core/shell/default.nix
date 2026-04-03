{pkgs, ...}: {
  imports = [
    ./starship.nix
    ./zsh.nix
  ];

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
    jq
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

  programs = {
    fzf.fuzzyCompletion = true; # Command-line fuzzy finder/search
    yazi.enable = true; # Terminal file manager
    pay-respects.enable = true;
    nix-index.enable = true;

    # nano fix
    nano.nanorc = ''
      unset mouse # Disable mouse support
    '';
  };
}

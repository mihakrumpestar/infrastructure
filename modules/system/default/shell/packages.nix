{ ... }:
{
  den.aspects.shell-packages = {
    nixos =
      { pkgs, ... }:
      {
        environment.etc."fastfetch/config.jsonc".source = ./fastfetch_config.jsonc;

        # CLI only
        environment.systemPackages = with pkgs; [
          # Basic
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
          zip

          # Development tools
          devbox # Supports zsh well
        ];

        programs = {
          fzf.fuzzyCompletion = true; # Command-line fuzzy finder/search
          yazi.enable = true; # Terminal file manager
          pay-respects.enable = true;
          nix-index.enable = true;

          # Disable mouse support in nano
          nano.nanorc = ''
            unset mouse
          '';
        };
      };
  };
}

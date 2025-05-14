{...}: {
  imports = [
    ./backup
    ./clipboard
    ./dead-mens-switch
    ./git
    ./ide
    ./password-manager
    ./scripts
    ./web-browser

    ./autostart.nix
    ./email.nix
    ./home.nix
    ./ssh.nix
    ./storage.nix
  ];
}

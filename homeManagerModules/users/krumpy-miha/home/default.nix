{...}: {
  imports = [
    ./backup
    ./clipboard
    ./dead-mens-switch
    ./git
    ./ide
    ./llm
    ./password-manager
    ./scripts
    ./web-browser

    ./autostart.nix
    ./home.nix
    ./ssh.nix
    ./storage.nix
  ];
}

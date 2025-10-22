{
  vars,
  config,
  ...
}: {
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

  # Store-secrets
  my.store-secrets.secretsFile = /${vars.secretsDir}/secrets/users/${config.home.username}/store-secrets.nix;
}

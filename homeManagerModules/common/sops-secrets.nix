{
  config,
  #osConfig,
  vars,
  ...
}: {
  # SOPS
  sops = {
    defaultSopsFile = /${vars.secretsDir}/secrets/${config.home.username}/secrets.sops.yml;
    age = {
      keyFile = "/home/${config.home.username}/.config/sops-nix/key.txt";
      sshKeyPaths = [];
    };
    gnupg.sshKeyPaths = [];
  };
  # Secrets are decrpyted on runtime to /run/user/<UID>/secrets.d/<home-manager ID>

  # Store-secrets
  my.store-secrets.secretsFile = /${vars.secretsDir}/secrets/${config.home.username}/store-secrets.nix;
}

{
  config,
  vars,
  ...
}: let
  platform =
    if config.my.client.enable
    then "clients"
    else if config.my.server.enable
    then "servers"
    else throw "Neither client nor server enabled";
in {
  sops = {
    defaultSopsFile = /${vars.secretsDir}/secrets/root/${platform}/secrets.sops.yml;
    age = {
      keyFile = "/var/lib/sops-nix/key.txt";
      sshKeyPaths = [];
    };
    gnupg.sshKeyPaths = [];
  };

  # Store-secrets
  my.store-secrets.secretsFile = "${vars.secretsDir}/secrets/root/${platform}/store-secrets.nix";

  security.tpm2 = {
    enable = true;
    pkcs11.enable = true; # expose /run/current-system/sw/lib/libtpm2_pkcs11.so
    tctiEnvironment.enable = true; # TPM2TOOLS_TCTI and TPM2_PKCS11_TCTI env variables
  };
  # users.users.YOUR_USER.extraGroups = ["tss"]; # tss group has access to TPM devices
}

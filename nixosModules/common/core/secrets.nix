{
  pkgs,
  vars,
  hostName,
  ...
}: let
  age_host_identity = pkgs.writeText "age_identitiy" (builtins.readFile /${vars.secretsDir}/secrets/hosts/${hostName}.txt);
in {
  security.tpm2 = {
    enable = true;
    pkcs11.enable = true; # expose /run/current-system/sw/lib/libtpm2_pkcs11.so
    tctiEnvironment.enable = true; # TPM2TOOLS_TCTI and TPM2_PKCS11_TCTI env variables
  };
  # users.users.YOUR_USER.extraGroups = ["tss"]; # tss group has access to TPM devices

  age = {
    identityPaths = [age_host_identity];
    ageBin = "PATH=${pkgs.age-plugin-tpm}/bin:$PATH ${pkgs.age}/bin/age";
  };

  home-manager.sharedModules = [
    {
      age = {
        identityPaths = [age_host_identity];
      };
    }
  ];

  environment.systemPackages = with pkgs; [
    age-plugin-tpm
  ];

  # Store-secrets
  my.store-secrets.secretsFile = "${vars.secretsDir}/secrets/users/root/store-secrets.nix";
}

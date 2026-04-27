{
  config,
  lib,
  pkgs,
  vars,
  hostName,
  ...
}: let
  # This is the TPM2 public key, not the secret
  age_host_identity = pkgs.writeText "age_identitiy" (builtins.readFile /${vars.secretsDir}/secrets/hosts/${hostName}.txt);

  # age does not find executable file "age-with-tpm" in env by default
  age-with-tpm = let
    wrapped = pkgs.age.withPlugins (ps: [ps.age-plugin-tpm]);
  in
    wrapped.overrideAttrs (old: {
      meta =
        (old.meta or {})
        // {
          mainProgram = "age";
        };
    });
in {
  # systemctl status agenix-install-secrets.service
  age = {
    identityPaths =
      if (config.my.hostSubType != "vm")
      then [age_host_identity]
      else config.services.openssh.hostKeys; # The default
    ageBin = lib.getExe age-with-tpm;
  };

  home-manager.sharedModules = [
    {
      # systemctl status --user agenix.service
      age = {
        inherit (config.age) identityPaths;
        package = age-with-tpm;
      };
    }
  ];

  environment.systemPackages = with pkgs; [
    age-with-tpm
    age-plugin-tpm
  ];

  services.userborn.enable = true; # For agenix

  # Store-secrets
  my.store-secrets = {
    enable = true;
    secretsFile = "${vars.secretsDir}/secrets/users/root/store-secrets.nix";
  };

  security.tpm2 = {
    enable = true;
    pkcs11.enable = true; # expose /run/current-system/sw/lib/libtpm2_pkcs11.so
    tctiEnvironment.enable = true; # TPM2TOOLS_TCTI and TPM2_PKCS11_TCTI env variables
  };
  # users.users.YOUR_USER.extraGroups = ["tss"]; # tss group has access to TPM devices
}

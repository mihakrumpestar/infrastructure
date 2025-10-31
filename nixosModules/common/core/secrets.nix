{
  config,
  lib,
  pkgs,
  vars,
  hostName,
  ...
}: let
  age_host_identity = pkgs.writeText "age_identitiy" (builtins.readFile /${vars.secretsDir}/secrets/hosts/${hostName}.txt);

  # age-with-tpm gets the following error on boot (but works on rebuild switch):
  # > age: error: tpm plugin: failed to read line: EOF
  # apperently was solved with migration to rage, age apperently has problem parsing multiple TPM recipients
  # https://github.com/Foxboron/age-plugin-tpm/issues/8
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

  rage-with-tpm =
    pkgs.runCommand "rage-with-tpm"
    {
      nativeBuildInputs = [pkgs.makeWrapper];
      propagatedBuildInputs = [pkgs.rage];
    }
    ''
      makeWrapper ${pkgs.rage}/bin/rage $out/bin/rage \
        --prefix PATH : "${pkgs.lib.makeBinPath [pkgs.age-plugin-tpm]}"
    ''
    // {meta.mainProgram = "rage";};
in {
  age = {
    identityPaths = [age_host_identity];
    ageBin = lib.getExe rage-with-tpm;
  };

  home-manager.sharedModules = [
    {
      # systemctl status --user agenix.service
      age = {
        inherit (config.age) identityPaths;
        package = rage-with-tpm;
      };
    }
  ];

  environment.systemPackages = with pkgs; [
    age-with-tpm
    rage-with-tpm
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

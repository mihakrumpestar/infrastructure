{ inputs, ... }:
let
  secretsDir = inputs.infrastructure-secrets;
in
{
  den.aspects.secrets = {
    nixos =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        inherit (config.networking) hostName;
        inherit (config.my.secrets) useTpm;

        # age does not find executable file "age-with-tpm" in env by default
        age-with-tpm =
          let
            wrapped = pkgs.age.withPlugins (ps: [ ps.age-plugin-tpm ]);
          in
          wrapped.overrideAttrs (old: {
            meta = (old.meta or { }) // {
              mainProgram = "age";
            };
          });
      in
      {
        options.my.secrets.useTpm = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether this host has a TPM2 chip available for age identity.";
        };

        config = {

          # systemctl status agenix-install-secrets.service
          age =
            lib.optionalAttrs useTpm {
              # builtins.readFile is eager — only set identityPaths for TPM hosts,
              # agenix defaults to SSH host keys otherwise
              identityPaths = [
                (pkgs.writeText "age_identitiy" (builtins.readFile (secretsDir + "/secrets/hosts/${hostName}.txt")))
              ];
            }
            // {
              ageBin = lib.getExe age-with-tpm;

              rekey = {
                hostPubkey = secretsDir + "/secrets/hosts/${hostName}.pub";
                masterIdentities = [
                  {
                    identity = "../infrastructure-secrets/secrets-plain/master-key.txt";
                  }
                ];
                storageMode = "derivation";
                agePlugins = lib.mkIf useTpm [
                  pkgs.age-plugin-tpm
                  # For some reason the dev decided that the signature in age is `age1tag1`, therefore age-plugin-tpm is not discovered and must be renamed to age-plugin-tag
                  (pkgs.runCommand "age-plugin-tag" { } ''
                    mkdir -p $out/bin
                    ln -s ${pkgs.age-plugin-tpm}/bin/age-plugin-tpm $out/bin/age-plugin-tag
                  '')
                ];
              };
            };

          home-manager.sharedModules = [
            {
              # systemctl status --user agenix.service
              age =
                lib.optionalAttrs useTpm {
                  inherit (config.age) identityPaths;
                }
                // {
                  package = age-with-tpm;
                  inherit (config.age) rekey;
                };
            }
          ];

          environment.systemPackages = with pkgs; [
            age-with-tpm
            age-plugin-tpm
          ];

          services.userborn.enable = true; # For agenix

          security.tpm2 = lib.mkIf useTpm {
            enable = true;
            pkcs11.enable = true; # expose /run/current-system/sw/lib/libtpm2_pkcs11.so
            tctiEnvironment.enable = true; # TPM2TOOLS_TCTI and TPM2_PKCS11_TCTI env variables
          };
          # users.users.YOUR_USER.extraGroups = ["tss"]; # tss group has access to TPM devices
        };
      };
  };
}

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

        # This is the TPM2 public key, not the secret
        age_host_identity = pkgs.writeText "age_identitiy" (
          builtins.readFile (secretsDir + "/secrets/hosts/${hostName}.txt")
        );

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
        config = {

          # systemctl status agenix-install-secrets.service
          age = {
            identityPaths = [ age_host_identity ];
            ageBin = lib.getExe age-with-tpm;

            rekey = {
              hostPubkey = secretsDir + "/secrets/hosts/${hostName}.pub";
              masterIdentities = [
                {
                  identity = "../infrastructure-secrets/secrets-plain/master-key.txt";
                  #pubkey = "age1uxr2hufap0qxrmm9vccj5s08yx7dc8eq0tgwg735qrq5ndxfvqcqgahjwq"; # TODO: remove if possible
                }
              ];
              storageMode = "derivation";
              agePlugins = [
                pkgs.age-plugin-tpm
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

          security.tpm2 = {
            enable = true;
            pkcs11.enable = true; # expose /run/current-system/sw/lib/libtpm2_pkcs11.so
            tctiEnvironment.enable = true; # TPM2TOOLS_TCTI and TPM2_PKCS11_TCTI env variables
          };
          # users.users.YOUR_USER.extraGroups = ["tss"]; # tss group has access to TPM devices
        };
      };
  };
}

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

        # sops resolves AGE-PLUGIN-* identities by executing age-plugin-<name>
        # from the unit PATH, so the plugin has to be in sops.age.plugins.
        # A TPM identity is a handle, the private key never leaves the TPM.
        identityFile = "${secretsDir}/secrets/hosts/${hostName}.txt";
      in
      {
        options.my.secrets.useTpm = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether this host has a TPM2 chip available for age identity.";
        };

        config = {
          # /etc is populated during activation, before any unit starts, so the
          # identity is in place for sops-install-secrets-for-users. That unit
          # is ordered before userborn, which in turn runs before
          # systemd-tmpfiles, so a tmpfiles-created identity would be too late.
          environment.etc = lib.mkIf useTpm {
            "sops-nix/age-keys.txt".source = identityFile;
          };

          sops.age = lib.mkIf useTpm {
            keyFile = "/etc/sops-nix/age-keys.txt";
            plugins = [ pkgs.age-plugin-tpm ];
            # No silent fallback to SSH host keys on TPM hosts.
            sshKeyPaths = [ ];
          };

          # The VPS hosts (vm-01, personal-vps-02) have no TPM and keep the
          # default sshKeyPaths (OpenSSH host keys). A recipient encrypted to
          # the raw ssh-ed25519 key cannot be unwrapped by that path: sops-nix
          # converts the private key to an age identity with ssh-to-age, so the
          # recipient in .sops.yaml must be the age1 form derived the same way.
          # GPG host keys are never used on any host.
          sops.gnupg.sshKeyPaths = [ ];

          assertions = lib.optional useTpm {
            assertion = builtins.pathExists identityFile;
            message = "sops: identity file missing for host ${hostName}: ${identityFile}";
          };

          # A TPM or driver hang here blocks sysinit and therefore sshd, and the
          # units are Type=oneshot with no timeout of their own.
          systemd.services.sops-install-secrets.serviceConfig.TimeoutStartSec = "60s";

          home-manager.sharedModules = [
            {
              # systemctl --user status sops-nix.service
              # The HM module decrypts on its own: same identity, its own
              # plugin path, and an explicit key source because its assertion
              # does not count plugins.
              sops.age = lib.mkIf useTpm {
                keyFile = "/etc/sops-nix/age-keys.txt";
                plugins = [ pkgs.age-plugin-tpm ];
              };
            }
          ];

          environment.systemPackages = with pkgs; [
            age
            age-plugin-tpm
          ];

          services.userborn.enable = true; # Reads hashedPasswordFile at boot

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

{ ... }:
{
  home.ssh = {
    homeManager =
      { config, lib, ... }:
      let
        cfg = config.my.ssh;
        gitIdentities = config.my.git.identities;
        identitiesDir = ".ssh/identities";
      in
      {
        options.my.ssh = {
          hosts = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  hostname = lib.mkOption { type = lib.types.str; };
                  user = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                  };
                  port = lib.mkOption {
                    type = lib.types.nullOr lib.types.int;
                    default = null;
                  };
                  identity = lib.mkOption { type = lib.types.str; };
                };
              }
            );
            default = { };
          };
        };

        config = {
          # Symlink .pub files to Nix store via home.file
          home.file =
            let
              hostIdentities = lib.mapAttrs' (
                name: entry: lib.nameValuePair "${identitiesDir}/${name}.pub" { text = entry.identity; }
              ) cfg.hosts;

              gitPubKeys = lib.mapAttrs' (
                name: entry: lib.nameValuePair "${identitiesDir}/git-${name}.pub" { text = entry.signingKey; }
              ) gitIdentities;
            in
            hostIdentities // gitPubKeys;

          # Ensure correct directory permissions for SSH
          home.activation.sshIdentities = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
            chmod 0700 ${config.home.homeDirectory}/${identitiesDir} || true
          '';

          programs.ssh = {
            enable = true;
            enableDefaultConfig = false;
            matchBlocks =
              let
                hostMatchBlocks = lib.mapAttrs (
                  name: entry:
                  {
                    inherit (entry) hostname;
                    identityFile = "~/${identitiesDir}/${name}.pub";
                    identitiesOnly = true;
                  }
                  // lib.optionalAttrs (entry.user != null) { inherit (entry) user; }
                  // lib.optionalAttrs (entry.port != null) { inherit (entry) port; }
                ) cfg.hosts;

                gitMatchBlocks = lib.mapAttrs' (
                  name: entry:
                  lib.nameValuePair name {
                    hostname = entry.url;
                    user = entry.email;
                    identityFile = "~/${identitiesDir}/git-${name}.pub";
                    identitiesOnly = true;
                  }
                ) gitIdentities;
              in
              hostMatchBlocks
              // gitMatchBlocks
              // {
                "local" = {
                  hostname = "localhost";
                  user = "root";
                  port = 22222;
                };
                "*" = {
                  forwardAgent = false;
                  addKeysToAgent = "no";
                  compression = false;
                  serverAliveInterval = 0;
                  serverAliveCountMax = 3;
                  hashKnownHosts = false;
                  userKnownHostsFile = "~/.ssh/known_hosts";
                  controlMaster = "no";
                  controlPath = "~/.ssh/master-%r@%n:%p";
                  controlPersist = "no";
                };
              };
          };
        };
      };
  };
}

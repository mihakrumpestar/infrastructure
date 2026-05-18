{ ... }:
{
  den.aspects.ssh = {
    homeManager =
      { config, lib, ... }:
      let
        cfg = config.my.ssh;
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

          git = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  name = lib.mkOption { type = lib.types.str; };
                  email = lib.mkOption { type = lib.types.str; };
                  url = lib.mkOption { type = lib.types.str; };
                  signingKey = lib.mkOption { type = lib.types.str; };
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

              gitIdentities = lib.mapAttrs' (
                name: entry: lib.nameValuePair "${identitiesDir}/git-${name}.pub" { text = entry.signingKey; }
              ) cfg.git;
            in
            hostIdentities // gitIdentities;

          # Ensure correct directory permissions for SSH
          home.activation.sshIdentities = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            chmod 0500 ${config.home.homeDirectory}/${identitiesDir} || true
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
                ) cfg.git;
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

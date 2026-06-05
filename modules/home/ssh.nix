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
            settings =
              let
                hostMatchBlocks = lib.mapAttrs (
                  name: entry:
                  {
                    HostName = entry.hostname;
                    IdentityFile = "~/${identitiesDir}/${name}.pub";
                    IdentitiesOnly = true;
                  }
                  // lib.optionalAttrs (entry.user != null) { User = entry.user; }
                  // lib.optionalAttrs (entry.port != null) { Port = entry.port; }
                ) cfg.hosts;

                gitMatchBlocks = lib.mapAttrs' (
                  name: entry:
                  lib.nameValuePair name {
                    HostName = entry.url;
                    User = entry.email;
                    IdentityFile = "~/${identitiesDir}/git-${name}.pub";
                    IdentitiesOnly = true;
                  }
                ) gitIdentities;
              in
              hostMatchBlocks
              // gitMatchBlocks
              // {
                "local" = {
                  HostName = "localhost";
                  User = "root";
                  Port = 22222;
                };
                "*" = {
                  ForwardAgent = false;
                  AddKeysToAgent = "no";
                  Compression = false;
                  ServerAliveInterval = 0;
                  ServerAliveCountMax = 3;
                  HashKnownHosts = false;
                  UserKnownHostsFile = "~/.ssh/known_hosts";
                  ControlMaster = "no";
                  ControlPath = "~/.ssh/master-%r@%n:%p";
                  ControlPersist = "no";
                };
              };
          };
        };
      };
  };
}

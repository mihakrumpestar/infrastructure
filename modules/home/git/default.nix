{ ... }:
{
  den.aspects.git = {
    homeManager =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        cfg = config.my.git.identities;
        gitConfigDir = "${config.xdg.configHome}/git";
      in
      {
        options.my.git.identities = lib.mkOption {
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

        config = {
          xdg.configFile =
            let
              allowedSignersText = lib.concatStrings (
                lib.mapAttrsToList (_: entry: "${entry.email} ${entry.signingKey}\n") cfg
              );

              identityConfigs = lib.mapAttrs' (
                name: entry:
                lib.nameValuePair "git/identities/${name}" {
                  text = ''
                    [user]
                      name = ${entry.name}
                      email = ${entry.email}
                      signingkey = ${entry.signingKey}

                    [core]
                      sshCommand = ssh -i ~/.ssh/identities/git-${name}.pub -o IdentitiesOnly=yes
                  '';
                }
              ) cfg;
            in
            identityConfigs
            // {
              "git/allowed_signers".text = allowedSignersText;
            };

          programs.git = {
            enable = true;
            lfs.enable = true;
            settings = {
              core = {
                editor = "codium --wait";
              };
              diff = {
                tool = "codium";
              };
              difftool = {
                codium = {
                  cmd = "codium --wait --diff $LOCAL $REMOTE";
                };
              };
              merge = {
                tool = "codium";
              };
              mergetool = {
                codium = {
                  cmd = "codium --wait $MERGED";
                };
              };
              commit = {
                gpgsign = "true";
              };
              gpg = {
                format = "ssh";
                ssh = {
                  allowedSignersFile = "${gitConfigDir}/allowed_signers";
                };
              };

              init = {
                defaultBranch = "main";
              };

              alias =
                let
                  mkAcpAlias =
                    prefix:
                    let
                      name = if prefix == "" then "ACP" else prefix;
                      script = pkgs.writeScriptBin "git-${name}" ''
                        #!/usr/bin/env bash
                        set -euo pipefail

                        COMMIT_FLAGS=()
                        MESSAGE=()

                        for arg in "$@"; do
                          if [[ "$arg" == -* ]]; then
                            COMMIT_FLAGS+=("$arg")
                          else
                            MESSAGE+=("$arg")
                          fi
                        done

                        MSG="''${MESSAGE[*]}"
                        ${if prefix != "" then ''MSG="${prefix}: $MSG"'' else ""}

                        if [ -z "''${MESSAGE[*]}" ]; then
                          echo 'Commit message is required';
                          exit 1;
                        fi

                        git add . && \
                        if [ ''${#COMMIT_FLAGS[@]} -gt 0 ]; then
                          git commit "''${COMMIT_FLAGS[@]}" -m "$MSG"
                        else
                          git commit -m "$MSG"
                        fi && \
                        git push
                      '';
                    in
                    "!${script}/bin/git-${name}";
                in
                {
                  acp = mkAcpAlias "";
                  feat = mkAcpAlias "feat";
                  fix = mkAcpAlias "fix";
                  docs = mkAcpAlias "docs";
                  refactor = mkAcpAlias "refactor";
                  test = mkAcpAlias "test";
                  chore = mkAcpAlias "chore";
                  setuser =
                    let
                      gitSetUser = pkgs.writeScriptBin "git-setuser" (builtins.readFile ./setuser.sh);
                    in
                    "!${gitSetUser}/bin/git-setuser";
                };
            };
          };
        };
      };
  };
}

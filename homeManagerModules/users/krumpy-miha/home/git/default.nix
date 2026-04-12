{
  config,
  pkgs,
  ...
}: let
  store-secrets = config.my.store-secrets.secrets;

  sshI = store-secrets.ssh.identities or {};
  sshU = store-secrets.ssh.users or {};
in {
  home.file = {
    ".ssh/allowed_signers".text = ''
      ${sshU.personal.email}
      ${sshU.fri.email}
    '';
    ".git/personal".text = ''
      [user]
        name = ${sshU.personal.name}
        email = ${sshU.personal.email}
        signingkey = ${sshI.git.personal}
    '';
    ".git/fri".text = ''
      [user]
        name = ${sshU.fri.name}
        email = ${sshU.fri.email}
        signingkey = ${sshI.git.fri}
    '';
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
          allowedSignersFile = config.home.file.".ssh/allowed_signers".target;
        };
      };

      init = {
        defaultBranch = "main";
      };

      url = let
        inherit (store-secrets.git) personal;
        inherit (store-secrets.git) fri;
        inherit (store-secrets.git) company_01;
      in {
        "ssh://git@github_personal/${personal}" = {
          insteadOf = "https://github.com/${personal}";
        };
        "git@github_personal:${personal}" = {
          insteadOf = "git@github.com:${personal}";
        };

        "ssh://git@github_fri/${fri}" = {
          insteadOf = "https://github.com/${fri}";
        };
        "git@github_fri:${fri}" = {
          insteadOf = "git@github.com:${fri}";
        };

        "ssh://git@github_personal/${company_01}" = {
          insteadOf = "https://github.com/${company_01}";
        };
        "git@github_personal:${company_01}" = {
          insteadOf = "git@github.com:${company_01}";
        };
      };
      alias = let
        mkAcpAlias = prefix: let
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
        in "!${script}/bin/git-${name}";
      in {
        acp = mkAcpAlias "";
        feat = mkAcpAlias "feat";
        fix = mkAcpAlias "fix";
        docs = mkAcpAlias "docs";
        refactor = mkAcpAlias "refactor";
        test = mkAcpAlias "test";
        chore = mkAcpAlias "chore";
        setuser = let
          gitSetUser = pkgs.writeScriptBin "git-setuser" (builtins.readFile ./setuser.sh);
        in "!${gitSetUser}/bin/git-setuser";
      };
    };
  };
}

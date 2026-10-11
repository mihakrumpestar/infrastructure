{ ... }:
{
  home.git = {
    homeManager =
      { pkgs, ... }:
      {
        # Per-identity git configs (~/.config/git/keepass-identities/*) and the SSH
        # signing trust file are generated from KeePassXC by
        # programs.ssh-config-gen. A repo whose remote uses an identity's SSH
        # alias (git@<alias>:owner/repo.git) picks up that identity automatically.

        # Bare filter commands below invoke git-lfs via PATH; keep it installed
        # (lfs.enable = false no longer installs it into the user profile)
        home.packages = [ pkgs.git-lfs ];
        programs.git = {
          enable = true;

          # Disabled: HM's default writes absolute /nix/store paths, which
          # git-lfs's own `install` validation rejects by strict equality
          # (warning + exit 2 on every `git lfs install`, surfaced by e.g.
          # GitHub Desktop's startup check as an error dialog).
          lfs.enable = false;

          settings = {
            core = {
              editor = "codium --wait";
            };

            # Bare command names exactly as git-lfs expects them; requires
            # git-lfs on PATH wherever the filter runs
            "filter.lfs" = {
              clean = "git-lfs clean -- %f";
              smudge = "git-lfs smudge -- %f";
              process = "git-lfs filter-process";
              required = "true";
            };
            diff = {
              tool = "codium";
            };
            difftool = {
              codium = {
                cmd = "codium --wait --diff $LOCAL $REMOTE";
              };
            };
            commit = {
              gpgsign = "true";
            };
            rebase = {
              gpgsign = "true";
            };
            merge = {
              tool = "codium";
              gpgSign = "true";
            };
            mergetool = {
              codium = {
                cmd = "codium --wait $MERGED";
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
              };
          };
        };
      };
  };
}

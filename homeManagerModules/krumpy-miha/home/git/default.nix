{
  config,
  pkgs,
  home,
  ...
}: let
  sshI = config.my.store-secrets.secrets.ssh.identities;
  sshU = config.my.store-secrets.secrets.ssh.users;
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
    extraConfig = {
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
        inherit (config.my.store-secrets.secrets.git) personal;
        inherit (config.my.store-secrets.secrets.git) fri;
        inherit (config.my.store-secrets.secrets.git) company_01;
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
    };
    aliases = {
      #build = ''!a() {\nlocal _scope _attention _message\nwhile [ $# -ne 0 ]; do\ncase $1 in\n  -s | --scope )\n    if [ -z $2 ]; then\n      echo \"Missing scope!\"\n      return 1\n    fi\n    _scope=\"$2\"\n    shift 2\n    ;;\n  -a | --attention )\n    _attention=\"!\"\n    shift 1\n    ;;\n  * )\n    _message=\"${_message} $1\"\n    shift 1\n    ;;\nesac\ndone\ngit commit -m \"build${_scope:+(${_scope})}${_attention}:${_message}\"\n}; a'';
      #chore = ''!a() {\nlocal _scope _attention _message\nwhile [ $# -ne 0 ]; do\ncase $1 in\n  -s | --scope )\n    if [ -z $2 ]; then\n      echo \"Missing scope!\"\n      return 1\n    fi\n    _scope=\"$2\"\n    shift 2\n    ;;\n  -a | --attention )\n    _attention=\"!\"\n    shift 1\n    ;;\n  * )\n    _message=\"${_message} $1\"\n    shift 1\n    ;;\nesac\ndone\ngit commit -m \"chore${_scope:+(${_scope})}${_attention}:${_message}\"\n}; a'';
      #ci = ''!a() {\nlocal _scope _attention _message\nwhile [ $# -ne 0 ]; do\ncase $1 in\n  -s | --scope )\n    if [ -z $2 ]; then\n      echo \"Missing scope!\"\n      return 1\n    fi\n    _scope=\"$2\"\n    shift 2\n    ;;\n  -a | --attention )\n    _attention=\"!\"\n    shift 1\n    ;;\n  * )\n    _message=\"${_message} $1\"\n    shift 1\n    ;;\nesac\ndone\ngit commit -m \"ci${_scope:+(${_scope})}${_attention}:${_message}\"\n}; a'';
      #docs = ''!a() {\nlocal _scope _attention _message\nwhile [ $# -ne 0 ]; do\ncase $1 in\n  -s | --scope )\n    if [ -z $2 ]; then\n      echo \"Missing scope!\"\n      return 1\n    fi\n    _scope=\"$2\"\n    shift 2\n    ;;\n  -a | --attention )\n    _attention=\"!\"\n    shift 1\n    ;;\n  * )\n    _message=\"${_message} $1\"\n    shift 1\n    ;;\nesac\ndone\ngit commit -m \"docs${_scope:+(${_scope})}${_attention}:${_message}\"\n}; a'';
      #feat = ''!a() {\nlocal _scope _attention _message\nwhile [ $# -ne 0 ]; do\ncase $1 in\n  -s | --scope )\n    if [ -z $2 ]; then\n      echo \"Missing scope!\"\n      return 1\n    fi\n    _scope=\"$2\"\n    shift 2\n    ;;\n  -a | --attention )\n    _attention=\"!\"\n    shift 1\n    ;;\n  * )\n    _message=\"${_message} $1\"\n    shift 1\n    ;;\nesac\ndone\ngit commit -m \"feat${_scope:+(${_scope})}${_attention}:${_message}\"\n}; a'';
      #fix = "!a() {\nlocal _scope _attention _message\nwhile [ $# -ne 0 ]; do\ncase $1 in\n  -s | --scope )\n    if [ -z $2 ]; then\n      echo \"Missing scope!\"\n      return 1\n    fi\n    _scope=\"$2\"\n    shift 2\n    ;;\n  -a | --attention )\n    _attention=\"!\"\n    shift 1\n    ;;\n  * )\n    _message=\"${_message} $1\"\n    shift 1\n    ;;\nesac\ndone\ngit commit -m \"fix${_scope:+(${_scope})}${_attention}:${_message}\"\n}; a";
      #perf = "!a() {\nlocal _scope _attention _message\nwhile [ $# -ne 0 ]; do\ncase $1 in\n  -s | --scope )\n    if [ -z $2 ]; then\n      echo \"Missing scope!\"\n      return 1\n    fi\n    _scope=\"$2\"\n    shift 2\n    ;;\n  -a | --attention )\n    _attention=\"!\"\n    shift 1\n    ;;\n  * )\n    _message=\"${_message} $1\"\n    shift 1\n    ;;\nesac\ndone\ngit commit -m \"perf${_scope:+(${_scope})}${_attention}:${_message}\"\n}; a";
      #refactor = "!a() {\nlocal _scope _attention _message\nwhile [ $# -ne 0 ]; do\ncase $1 in\n  -s | --scope )\n    if [ -z $2 ]; then\n      echo \"Missing scope!\"\n      return 1\n    fi\n    _scope=\"$2\"\n    shift 2\n    ;;\n  -a | --attention )\n    _attention=\"!\"\n    shift 1\n    ;;\n  * )\n    _message=\"${_message} $1\"\n    shift 1\n    ;;\nesac\ndone\ngit commit -m \"refactor${_scope:+(${_scope})}${_attention}:${_message}\"\n}; a";
      #rev = "!a() {\nlocal _scope _attention _message\nwhile [ $# -ne 0 ]; do\ncase $1 in\n  -s | --scope )\n    if [ -z $2 ]; then\n      echo \"Missing scope!\"\n      return 1\n    fi\n    _scope=\"$2\"\n    shift 2\n    ;;\n  -a | --attention )\n    _attention=\"!\"\n    shift 1\n    ;;\n  * )\n    _message=\"${_message} $1\"\n    shift 1\n    ;;\nesac\ndone\ngit commit -m \"revert${_scope:+(${_scope})}${_attention}:${_message}\"\n}; a";
      #style = "!a() {\nlocal _scope _attention _message\nwhile [ $# -ne 0 ]; do\ncase $1 in\n  -s | --scope )\n    if [ -z $2 ]; then\n      echo \"Missing scope!\"\n      return 1\n    fi\n    _scope=\"$2\"\n    shift 2\n    ;;\n  -a | --attention )\n    _attention=\"!\"\n    shift 1\n    ;;\n  * )\n    _message=\"${_message} $1\"\n    shift 1\n    ;;\nesac\ndone\ngit commit -m \"style${_scope:+(${_scope})}${_attention}:${_message}\"\n}; a";
      #test = "!a() {\nlocal _scope _attention _message\nwhile [ $# -ne 0 ]; do\ncase $1 in\n  -s | --scope )\n    if [ -z $2 ]; then\n      echo \"Missing scope!\"\n      return 1\n    fi\n    _scope=\"$2\"\n    shift 2\n    ;;\n  -a | --attention )\n    _attention=\"!\"\n    shift 1\n    ;;\n  * )\n    _message=\"${_message} $1\"\n    shift 1\n    ;;\nesac\ndone\ngit commit -m \"test${_scope:+(${_scope})}${_attention}:${_message}\"\n}; a";
      #wip = "!a() {\nlocal _scope _attention _message\nwhile [ $# -ne 0 ]; do\ncase $1 in\n  -s | --scope )\n    if [ -z $2 ]; then\n      echo \"Missing scope!\"\n      return 1\n    fi\n    _scope=\"$2\"\n    shift 2\n    ;;\n  -a | --attention )\n    _attention=\"!\"\n    shift 1\n    ;;\n  * )\n    _message=\"${_message} $1\"\n    shift 1\n    ;;\nesac\ndone\ngit commit -m \"wip${_scope:+(${_scope})}${_attention}:${_message}\"\n}; a";
      acp = let
        gitACP = pkgs.writeScriptBin "git-ACP" ''
          #!/usr/bin/env bash

          set -euo pipefail

          MESSAGE="$1"

          if [ -z "$MESSAGE" ]; then
            echo 'Commit message is required';
            return 1;
          fi;

          git add . && \
          git commit -m "$MESSAGE" && \
          git push;
        '';
      in "!${gitACP}/bin/git-ACP";
      setuser = let
        gitSetUser = pkgs.writeScriptBin "git-setuser" (builtins.readFile ./setuser.sh);
      in "!${gitSetUser}/bin/git-setuser";
    };
  };
}

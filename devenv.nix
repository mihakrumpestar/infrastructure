{ pkgs, ... }:
{
  packages = with pkgs; [
    deadnix
    flake-checker
    go-task
    mermaid-cli
    nixfmt-tree
    statix
    gitleaks
  ];

  # Python for scripts/flake_stats.py (tabulate and matplotlib imports) and
  # the PVE deploys (pyinfra).
  languages.python = {
    enable = true;
    package = pkgs.python313.withPackages (ps: [
      ps.matplotlib
      ps.pyinfra
      ps.tabulate
    ]);
  };

  # Interactive shells only: check out the private secrets repo on first entry.
  # `-t 0` skips CI and piped runs; the DEVENV_CMDLINE check skips
  # `devenv shell -- <cmd>`, `devenv test` and `devenv up`, which also run
  # enterShell. An existing checkout, including a manual clone, is left alone.
  enterShell = ''
    if [ -z "''${CI:-}" ] && [ -t 0 ] && [ "''${DEVENV_CMDLINE:-}" = "shell" ] &&
      [ ! -e "$DEVENV_ROOT/secrets" ]; then
      echo "Cloning infrastructure-secrets into $DEVENV_ROOT/secrets"
      git clone git@github-personal:mihakrumpestar/infrastructure-secrets.git "$DEVENV_ROOT/secrets" ||
        echo "warning: could not clone infrastructure-secrets, continuing" >&2
    fi
  '';

  # Git hooks are declared here and installed by devenv on shell entry.
  # The generated .pre-commit-config.yaml is gitignored.
  git-hooks.hooks.ci = {
    enable = true;
    entry = "task ci";
    language = "system";
    pass_filenames = false;
  };
}

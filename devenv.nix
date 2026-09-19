{ pkgs, ... }:
{
  packages = [
    pkgs.go-task
    pkgs.nixfmt-tree
    pkgs.deadnix
    pkgs.statix
    pkgs.mermaid-cli
    pkgs.hashrat
  ];

  # Python for scripts/flake_stats.py (tabulate and matplotlib imports).
  languages.python = {
    enable = true;
    package = pkgs.python313.withPackages (ps: [
      ps.tabulate
      ps.matplotlib
    ]);
  };

  # Git hooks are declared here and installed by devenv on shell entry.
  # The generated .pre-commit-config.yaml is gitignored.
  git-hooks.hooks.ci = {
    enable = true;
    entry = "task ci";
    language = "system";
    pass_filenames = false;
  };
}

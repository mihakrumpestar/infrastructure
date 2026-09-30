{ pkgs, ... }:
{
  packages = [
    pkgs.deadnix
    pkgs.flake-checker
    pkgs.go-task
    pkgs.mermaid-cli
    pkgs.nixfmt-tree
    pkgs.statix
  ];

  # Python for scripts/flake_stats.py (tabulate and matplotlib imports).
  languages.python = {
    enable = true;
    package = pkgs.python313.withPackages (ps: [
      ps.matplotlib
      ps.tabulate
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

# NixOS Infrastructure Scripts

This directory contains utility scripts for generating statistics and dependency graphs for the NixOS infrastructure repository.

## generate_stats.py

Generates comprehensive build statistics for all NixOS host configurations, including closure sizes, evaluation times, and package counts.

### Usage

```bash
task generate                    # Single run
task generate -- --runs 5        # 5 runs for averaging timing statistics
```

### Output

- Updates `README.md` between `<!-- STATS_START -->` and `<!-- STATS_END -->` markers
- Saves results to `generated/stats_TIMESTAMP/statistics.md`
- Generates timing graphs (bar chart, box plot) when `--runs > 1`

### Metrics Explained

#### Closure Size

Total disk space required for all dependencies of a host configuration.

```bash
nix build path:.#nixosConfigurations.<host>.config.system.build.toplevel --no-link --print-out-paths
nix path-info --closure-size <derivation>
```

The closure size includes:
- All packages in `environment.systemPackages`
- All packages in `home.packages` (for home-manager users)
- All transitive dependencies (libraries, runtime dependencies)
- System components (kernel, systemd, init scripts)
- Nix store metadata

#### Evaluation Time

Time to compute the Nix derivation (expression evaluation only, not building).

Measured from start to end of:
```bash
nix build path:.#nixosConfigurations.<host>.config.system.build.toplevel --no-link --print-out-paths
```

When run with `--runs N`, collects statistics (mean, median, std dev, min, max) across multiple runs.

#### System Pkgs (Package Count)

Count of packages in the system profile, using the same logic as [Fastfetch](https://github.com/fastfetch-cli/fastfetch) (a popular CLI system information tool):

1. Build the system toplevel:
   ```bash
   nix build path:.#nixosConfigurations.<host>.config.system.build.toplevel --print-out-paths
   ```

2. Get all runtime dependencies:
   ```bash
   nix-store -q --requisites <toplevel>
   ```

3. Filter each path using `is_valid_nix_pkg()`:
   - Must be a directory (not a file)
   - Exclude paths ending with `-doc`, `-man`, `-info`, `-dev`, `-bin` (documentation and development outputs)
   - Exclude `nixos-system-nixos-*` (the system wrapper itself)
   - Must contain a version pattern `-\d+\.\d+` (e.g., `firefox-125.0`, `git-2.44.0`)

This matches the implementation in [Fastfetch's packages_nix.c](https://github.com/fastfetch-cli/fastfetch/blob/dev/src/detection/packages/packages_nix.c).

**Example:** `firefox-125.0` passes, `firefox-doc` fails, `nixos-system-nixos-25.05` fails.

#### Home Pkgs (Package Count)

Count of packages in home-manager user profiles, using the same algorithm as System Pkgs:

1. Get home-manager users:
   ```bash
   nix eval --json 'path:.#nixosConfigurations.<host>.config.home-manager.users' --apply 'builtins.attrNames'
   ```

2. For each user, get the home profile path:
   ```bash
   nix eval --raw 'path:.#nixosConfigurations.<host>.config.home-manager.users.<user>.home.path'
   ```

3. Get all runtime dependencies:
   ```bash
   nix-store -q --requisites <home-path>
   ```

4. Apply the same `is_valid_nix_pkg()` filter

If a host has no home-manager users, this shows `-`.

#### System Refs / Home Refs

Total count of all Nix store paths (recursive dependencies) without filtering:

```bash
nix-store -q --requisites <path> | wc -l
```

This includes:
- All packages
- All libraries
- Development outputs
- Documentation
- Intermediate build dependencies

**Comparison:**
- System/Home Pkgs: Filtered count (actual packages)
- System/Home Refs: Unfiltered count (all store paths)

#### Closure Reuse Matrix

Percentage of shared dependencies between host configurations:

```
closure1 & closure2 / closure1 * 100
```

Where `closure1` and `closure2` are sets of `/nix/store/*` paths from `nix path-info --recursive <toplevel>`.

### Concurrency

Hosts are built in parallel using `ThreadPoolExecutor` with max workers equal to the number of hosts. Error handling implements fail-fast behavior.

---

## generate_deps.py

Generates a Mermaid dependency graph showing import relationships between Nix files in the repository.

### Usage

```bash
task generate-deps
```

### Output

- Updates `README.md` between `<!-- DEPS_START -->` and `<!-- DEPS_END -->` markers
- Saves Mermaid diagram to `generated/deps_TIMESTAMP/dependencies.mmd`
- Exports PNG to `generated/deps_TIMESTAMP/dependencies.png`

# NixOS Infrastructure Scripts

This directory contains utility scripts for generating statistics and dependency graphs for the NixOS infrastructure repository.

## flake_stats.py

Generates statistics for all NixOS host configurations: closure sizes, package counts,
closure reuse matrix, and deterministic eval benchmarks (sequential and simultaneous).

Uses `nix eval --option eval-cache false` for deterministic evaluation timing,
ensuring cache-free measurements across all runs.

### Usage

```bash
task generate                       # 3 runs (default), all hosts
task generate -- --runs 5           # 5 runs for statistics
task generate -- --hosts kiosk pi4  # specific hosts only
```

### Parameters

- `--runs N` — Number of eval runs per host per mode (default: 3)
- `--hosts h1 h2 ...` — Specific nixosConfigurations (default: all)

### Output

- Updates `README.md` between `<!-- STATS_START -->` and `<!-- STATS_END -->` markers
- Saves results to `generated/stats_TIMESTAMP/infrastructure-configurations-statistics.md`
- Generates eval comparison graphs (bar chart, box plot) to `generated/stats_TIMESTAMP/`

### How It Works

1. **Build** all hosts once (parallel) to collect closure size, package counts, and reuse data
2. **Sequential eval** — each host evaluated one at a time, N runs
3. **Simultaneous eval** — all hosts evaluated in parallel, N runs
4. Compare sequential vs simultaneous to measure concurrent evaluation overhead

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

#### Eval Performance

Time to evaluate the Nix expression (not build), measured deterministically using:

```bash
nix eval 'path:.#nixosConfigurations.<host>.config.system.build.toplevel.drvPath' --option eval-cache false
```

Two modes are benchmarked:
- **Sequential**: one host at a time (baseline, no interference)
- **Simultaneous**: all hosts in parallel (shows concurrent evaluation overhead)

Statistics (mean, median, std dev, min, max) are computed over N runs.

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

---

## flake_graph.py

Generates a Mermaid dependency graph showing aspect/include relationships between Nix files in the den-based flake structure.

### Usage

```bash
task generate-deps
```

### Output

- Updates `README.md` between `<!-- DEPS_START -->` and `<!-- DEPS_END -->` markers
- Saves Mermaid diagram to `generated/flake-graph_TIMESTAMP/infrastructure-flake-graph.md`
- Exports PDF to `generated/flake-graph_TIMESTAMP/infrastructure-flake-graph.pdf`

"""Collection and pure computation for the two stats tiers.

Single source of truth for repository paths, README markers, LOC areas, chart
stems and the host dataclasses. Every external call (nix, nix-store) lives
here; ``cli.py`` orchestrates and ``render.py`` / ``charts.py`` publish.
Optional metrics degrade gracefully by recording a reason instead of raising.
"""

from __future__ import annotations

import json
import os
import re
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field, fields
from functools import cache
from pathlib import Path

from .util import REPO_ROOT, Stage, Timing, nix_eval_json, nix_eval_raw, run

README_PATH = REPO_ROOT / "README.md"
#: Committed chart directory (the four SVGs the README references).
STATS_DIR = REPO_ROOT / "assets" / "stats"
GENERATED_DIR = REPO_ROOT / "generated"

#: README regions; everything between the markers is generated.
FAST_START = "<!-- FAST_START -->"
FAST_END = "<!-- FAST_END -->"
HEAVY_START = "<!-- HEAVY_START -->"
HEAVY_END = "<!-- HEAVY_END -->"

#: Generated run directory family, pruned oldest-first.
RUN_PREFIXES = ("flake-graph_",)

#: LOC table sources. An area with a subdir tuple gets one row per subdir plus
#: a total row; ``None`` counts the area as a whole. Markdown is skipped.
LOC_FILES = ("flake.nix",)
LOC_AREAS: tuple[tuple[str, tuple[str, ...] | None], ...] = (
    ("modules", ("den.nix", "hosts", "system", "home", "users")),
    ("packages", None),
    ("lib", None),
)

#: Chart stems per tier: the fast LOC chart and the three heavy charts.
FAST_CHART_STEMS = ("loc-by-area",)
HEAVY_CHART_STEMS = ("closure-size", "package-counts", "closure-reuse")

HOST_MATRIX_TIMEOUT = 900.0


@dataclass
class LocEntry:
    """One LOC table row: component label and its non-blank line count."""

    component: str
    lines: int


@dataclass
class HostFacts:
    """One row of the per-host matrix, from a single nix eval over all hosts.

    Only fields the README renders are collected: desktop, home-manager
    users, service count and secret count.
    """

    host: str
    de: str | None = None
    hmUsers: list[str] = field(default_factory=list)
    services: int | None = None
    ageSecrets: int | None = None


@dataclass
class HostClosure:
    """Closure metrics for one host toplevel; keys in ``closures`` name the host."""

    size_bytes: int = 0
    systemPackages: int = 0
    homePackages: int = 0
    error: str | None = None


@dataclass
class ReuseSummary:
    """Reuse matrix plus union vs sum consolidation savings.

    matrix[row_host][column_host] is the percent of the row closure contained
    in the column closure, or None on the diagonal.
    """

    hosts: list[str] = field(default_factory=list)
    matrix: dict[str, dict[str, float | None]] = field(default_factory=dict)
    unionBytes: int = 0
    sumBytes: int = 0
    savingsPct: float = 0.0


@dataclass
class Measurements:
    """Heavy tier results; ``measuredAt`` is the run start timestamp."""

    measuredAt: str = ""
    hostFacts: list[HostFacts] = field(default_factory=list)
    closures: dict[str, HostClosure] = field(default_factory=dict)
    reuse: ReuseSummary = field(default_factory=ReuseSummary)

    def hosts(self) -> list[str]:
        return [facts.host for facts in self.hostFacts]


#: One nix eval producing the per-host matrix. ``host`` is the eval key;
#: every other field goes through ``safe`` so a missing option yields null
#: instead of failing the eval.
HOST_MATRIX_APPLY = """
cfg:
let
  safe = e: let r = builtins.tryEval e; in if r.success then r.value else null;
  mkHost = h: let
    c = cfg.${h}.config;
    plasma = safe c.services.desktopManager.plasma6.enable;
    gnome = safe c.services.desktopManager.gnome.enable;
  in {
    host = h;
    de = if plasma == true then "plasma" else if gnome == true then "gnome" else null;
    hmUsers = safe (builtins.attrNames c.home-manager.users);
    services = safe (builtins.length (builtins.attrNames c.systemd.services));
    ageSecrets = safe (builtins.length (builtins.attrNames c.age.secrets));
  };
in
map mkHost (builtins.attrNames cfg)
"""


def collect_host_matrix() -> dict[str, HostFacts]:
    """One eval over all hosts, keyed by host (order = eval attr order)."""
    data = nix_eval_json(
        "nixosConfigurations", apply=HOST_MATRIX_APPLY, timeout=HOST_MATRIX_TIMEOUT
    )
    if not isinstance(data, list):
        return {}
    facts: dict[str, HostFacts] = {}
    for row in data:
        if not isinstance(row, dict) or not isinstance(row.get("host"), str):
            continue
        # HostFacts field names mirror the eval's attribute names.
        values = {f.name: row.get(f.name) for f in fields(HostFacts)}
        values["hmUsers"] = list(row.get("hmUsers") or [])
        facts[row["host"]] = HostFacts(**values)
    return facts


# --- Closures ---------------------------------------------------------------


def requisites(path: str) -> list[str]:
    result = run(["nix-store", "-q", "--requisites", path])
    if result.returncode == 0 and result.stdout.strip():
        return result.stdout.strip().split("\n")
    return []


def _build_toplevel(host: str) -> tuple[str | None, str | None]:
    build = run(
        [
            "nix",
            "build",
            f"path:.#nixosConfigurations.{host}.config.system.build.toplevel",
            "--no-link",
            "--print-out-paths",
        ]
    )
    if build.returncode != 0:
        return None, build.stderr.strip() or "Build failed"
    return build.stdout.strip(), None


def _measure_closure(toplevel: str) -> tuple[dict[str, int], str | None]:
    """Parse ``nix path-info --json --recursive`` into ({store path: narSize}, error).

    Accepts both JSON forms Nix emits: format 1 (object keyed by path) and
    format 2 (list of objects with a path field).
    """
    path_info = run(
        ["nix", "path-info", "--json", "--json-format", "1", "--recursive", toplevel]
    )
    if path_info.returncode != 0:
        return {}, "path-info failed"
    try:
        data = json.loads(path_info.stdout)
    except json.JSONDecodeError:
        data = {}
    if isinstance(data, dict):
        sizes = {
            path: int(info.get("narSize", 0))
            for path, info in data.items()
            if isinstance(info, dict)
        }
    else:
        sizes = {
            str(item["path"]): int(item.get("narSize", 0))
            for item in data
            if isinstance(item, dict) and item.get("path")
        }
    return sizes, None if sizes else "empty closure"


def home_counts(paths: dict[str, int], facts: HostFacts) -> int:
    """Home package count for one host, with the eval fallback.

    A single home-manager profile already reachable from the system toplevel
    is measured in place; otherwise each user's ``home.path`` is evaluated.
    """
    if not facts.hmUsers:
        return 0
    profiles = sorted(
        path for path in paths if path.rsplit("/", 1)[-1].endswith("-home-manager-path")
    )
    if len(facts.hmUsers) == 1 and len(profiles) == 1:
        return count_packages(requisites(profiles[0]))
    packages = 0
    for user in facts.hmUsers:
        home_path = nix_eval_raw(
            f"nixosConfigurations.{facts.host}.config.home-manager.users.{user}.home.path"
        )
        if home_path:
            packages += count_packages(requisites(home_path))
    return packages


def _parallel(hosts: list[str], work) -> dict:
    with ThreadPoolExecutor(max_workers=max(1, len(hosts))) as executor:
        futures = {executor.submit(work, host): host for host in hosts}
        return {futures[future]: future.result() for future in as_completed(futures)}


def build_closures(
    hosts: list[str], facts: dict[str, HostFacts], timing: Timing
) -> tuple[dict[str, HostClosure], dict[str, dict[str, int]]]:
    """Build all hosts in parallel; failures are recorded, never raised.

    System counts derive from the measured closure (path-info set == requisites
    set); only the separate home profiles need another traversal.
    """
    with timing.stage(Stage.CLOSURE_BUILDS):
        builds = _parallel(hosts, _build_toplevel)
    size_hosts = [host for host in hosts if builds[host][0]]
    with timing.stage(Stage.CLOSURE_SIZES):
        sizes = _parallel(size_hosts, lambda host: _measure_closure(builds[host][0]))
    ref_hosts = [host for host in size_hosts if not sizes[host][1]]
    system = {host: count_packages(list(sizes[host][0])) for host in ref_hosts}
    with timing.stage(Stage.CLOSURE_REFS):
        homes = _parallel(ref_hosts, lambda host: home_counts(sizes[host][0], facts[host]))

    closures: dict[str, HostClosure] = {}
    host_paths: dict[str, dict[str, int]] = {}
    for host in hosts:
        _, build_error = builds[host]
        paths, size_error = sizes.get(host, ({}, "build produced no toplevel"))
        error = build_error or size_error
        if error:
            closures[host] = HostClosure(error=error)
            host_paths[host] = {}
            continue
        closures[host] = HostClosure(
            size_bytes=sum(paths.values()),
            systemPackages=system[host],
            homePackages=homes[host],
        )
        host_paths[host] = paths
    return closures, host_paths


# --- LOC --------------------------------------------------------------------

#: Markdown is documentation, bytecode and caches are generated: never source.
LOC_SKIP_SUFFIXES = (".md",)
LOC_SKIP_DIRS = ("__pycache__",)
LOC_SKIP_BINARY_SUFFIXES = (".pyc", ".pyo")


def count_loc(path: Path) -> int:
    """Count non-blank lines under path, skipping docs and generated files."""
    if not path.exists():
        return 0
    if path.is_file():
        if path.suffix in LOC_SKIP_SUFFIXES + LOC_SKIP_BINARY_SUFFIXES:
            return 0
        try:
            content = path.read_text()
        except (UnicodeDecodeError, OSError):
            return 0  # Binary asset, not source code.
        return sum(1 for line in content.splitlines() if line.strip())
    return sum(
        count_loc(child)
        for child in sorted(path.iterdir())
        if (child.is_file() and child.suffix not in LOC_SKIP_SUFFIXES + LOC_SKIP_BINARY_SUFFIXES)
        or (child.is_dir() and child.name not in LOC_SKIP_DIRS)
    )


def build_loc_entries(root: Path) -> list[LocEntry]:
    entries = [LocEntry(name, count_loc(root / name)) for name in LOC_FILES]
    total = sum(entry.lines for entry in entries)
    for area, subdirs in LOC_AREAS:
        if subdirs is None:
            lines = count_loc(root / area)
            entries.append(LocEntry(f"{area} (total)", lines))
        else:
            lines = 0
            for sub in subdirs:
                sub_lines = count_loc(root / area / sub)
                entries.append(LocEntry(f"{area}/{sub}", sub_lines))
                lines += sub_lines
            entries.append(LocEntry(f"{area} (total)", lines))
        total += lines
    entries.append(LocEntry("**Total**", total))
    return entries


def loc_leaf_entries(entries: list[LocEntry]) -> list[LocEntry]:
    """Leaf LOC rows for the chart: no double counting.

    An ``(total)`` row is dropped only when its area already has child rows;
    a childless area total holds its lines alone and is kept. The grand total
    is always dropped.
    """
    covered = {e.component.split("/", 1)[0] for e in entries if "/" in e.component}
    return [
        entry
        for entry in entries
        if entry.component.strip("*") != "Total"
        and not (
            entry.component.endswith(" (total)")
            and entry.component[: -len(" (total)")] in covered
        )
    ]


# --- Package counting and reuse ---------------------------------------------

#: Same heuristic as fastfetch's packages_nix.c: a '-<major>.<minor>' segment.
VERSION_RE = re.compile(r"-\d+\.\d+")

_EXCLUDED_SUFFIXES = ("-doc", "-man", "-info", "-dev", "-bin")
_EXCLUDED_PREFIXES = ("nixos-system-nixos-",)


@cache
def _cached_isdir(path: str) -> bool:
    return os.path.isdir(path)


def count_packages(paths: list[str], is_dir=_cached_isdir) -> int:
    """Store paths that count as packages, following the fastfetch heuristic.

    The 32 character store hash is dropped, docs/debug outputs are excluded
    and a '-<major>.<minor>' version segment is required.
    """
    packages = 0
    for path in paths:
        name = path.rsplit("/", 1)[-1]
        if len(name) > 33 and name[32] == "-":
            name = name[33:]
        if (
            is_dir(path)
            and not name.startswith(_EXCLUDED_PREFIXES)
            and not name.endswith(_EXCLUDED_SUFFIXES)
            and VERSION_RE.search(name)
        ):
            packages += 1
    return packages


#: Bytes per gibibyte; every closure figure in the README is in GiB.
BYTES_PER_GIB = 1024**3


def gib(size_bytes: int) -> float:
    """Size in gibibytes, the unit of every closure figure."""
    return size_bytes / BYTES_PER_GIB


def fmt_gib(size_bytes: int) -> str:
    """Gibibytes with two decimals, the CLI log format."""
    return f"{gib(size_bytes):.2f} GiB"


def build_reuse_summary(
    hosts: list[str],
    host_paths: dict[str, dict[str, int]],
    size_bytes: dict[str, int],
) -> ReuseSummary:
    """Reuse matrix plus union vs sum consolidation savings.

    ``host_paths`` maps each host to its closure paths with narSize. Cell
    (row, column) is the percentage of the row closure contained in the
    column closure, matching the published table.
    """
    path_sets = {host: set(host_paths.get(host, {})) for host in hosts}
    matrix: dict[str, dict[str, float | None]] = {}
    for row in hosts:
        total = len(path_sets[row])
        matrix[row] = {
            column: (
                None
                if row == column
                else 0.0
                if total == 0
                else len(path_sets[row] & path_sets[column]) * 100 / total
            )
            for column in hosts
        }
    union: set[str] = set().union(*path_sets.values()) if path_sets else set()
    sizes_by_path: dict[str, int] = {}
    for host in hosts:
        for path, size in host_paths.get(host, {}).items():
            sizes_by_path.setdefault(path, size)
    union_bytes = sum(sizes_by_path.get(path, 0) for path in union)
    sum_bytes = sum(size_bytes.get(host, 0) for host in hosts)
    savings = max(sum_bytes - union_bytes, 0)
    return ReuseSummary(
        hosts=list(hosts),
        matrix=matrix,
        unionBytes=union_bytes,
        sumBytes=sum_bytes,
        savingsPct=(savings * 100 / sum_bytes) if sum_bytes else 0.0,
    )

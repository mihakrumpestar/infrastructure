#!/usr/bin/env python3
"""
NixOS Configuration Statistics Generator

Evaluates and builds all hosts, measures eval time (sequential and simultaneous),
closure sizes, package counts, and closure reuse percentages.

Uses `nix eval --option eval-cache false` for deterministic evaluation timing.

Usage:
    task generate                       # 3 runs (default)
    task generate -- --runs 5           # 5 runs for statistics
    task generate -- --hosts kiosk pi4  # specific hosts only
"""

import subprocess
import json
import time
import sys
import os
import re
import argparse
import statistics
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # type: ignore[import-untyped]
import numpy as np
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from dataclasses import dataclass, field
from datetime import datetime
from tabulate import tabulate  # type: ignore[import-untyped]

REPO_ROOT = Path(__file__).parent.parent
README_PATH = REPO_ROOT / "README.md"
STATS_START = "<!-- STATS_START -->"
STATS_END = "<!-- STATS_END -->"
VERSION_RE = re.compile(r"-\d+\.\d+")
ISDIR_CACHE: dict[str, bool] = {}
EVAL_NO_CACHE = ["--option", "eval-cache", "false"]

LOC_DIRS = {
    "modules": ["den.nix", "hosts", "system", "home", "users"],
    "packages": None,
    "lib": None,
}


def run(cmd: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, cwd=cwd or REPO_ROOT)


def nix_eval(attr: str, apply: str | None = None, raw: bool = False) -> str:
    cmd = ["nix", "eval", "--json" if not raw else "--raw", f"path:.#{attr}"]
    if apply:
        cmd += ["--apply", apply]
    r = run(cmd)
    return r.stdout.strip() if r.returncode == 0 else ""


def get_git_hash() -> str:
    r = run(["git", "rev-parse", "HEAD"])
    return r.stdout.strip() if r.returncode == 0 else "unknown"


def get_cpu_model() -> str:
    try:
        for line in Path("/proc/cpuinfo").read_text().splitlines():
            if line.startswith("model name"):
                return line.split(":", 1)[1].strip()
    except Exception:
        pass
    return "unknown"


def get_disk_info() -> str:
    model = "unknown"
    serial = ""
    try:
        r = subprocess.run(["lspci"], capture_output=True, text=True)
        if r.returncode == 0:
            for line in r.stdout.splitlines():
                if "Non-Volatile" in line or "NVMe" in line or "SSD" in line or "SATA" in line:
                    model = line.split(": ", 1)[1].strip()
                    break
    except Exception:
        pass
    try:
        r = subprocess.run(["lsblk", "-d", "-o", "MODEL", "-n"],
                           capture_output=True, text=True)
        if r.returncode == 0:
            for line in r.stdout.strip().splitlines():
                s = line.strip()
                if s:
                    serial = s
                    break
    except Exception:
        pass
    return f"{model} (SN: {serial})" if serial else model


def get_memory() -> str:
    try:
        block_size_path = Path("/sys/devices/system/memory/block_size_bytes")
        if block_size_path.exists():
            block_bytes = int(block_size_path.read_text().strip(), 16)
            blocks = sum(1 for d in Path("/sys/devices/system/memory").iterdir()
                         if d.name.startswith("memory"))
            gib = blocks * block_bytes / (1024 ** 3)
            return f"{gib:.0f} GiB"
    except Exception:
        pass
    try:
        for line in Path("/proc/meminfo").read_text().splitlines():
            if line.startswith("MemTotal"):
                gib = int(line.split()[1]) / (1024 ** 2)
                return f"{gib:.0f} GiB"
    except Exception:
        pass
    return "unknown"


def count_loc(path: Path) -> int:
    if not path.exists():
        return 0
    if path.is_file():
        return sum(1 for line in path.read_text().splitlines() if line.strip())
    return sum(
        count_loc(f)
        for f in sorted(path.iterdir())
        if (f.is_file() and f.suffix != ".md") or f.is_dir()
    )


def build_loc_table() -> tuple[str, list[list[str | int]]]:
    header = f"""
## Lines of Code

**Table 1:** Non-blank lines across the flake's source tree.

LOC excludes blank lines but includes comments. All file types are counted
(`.nix`, `.json`, `.jsonc`, `.sh`, `.ini`, etc.) except Markdown (`.md`).
"""
    rows: list[list[str | int]] = []
    grand_total = count_loc(REPO_ROOT / "flake.nix")
    rows.append(["flake.nix", grand_total])

    for top_dir, subdirs in LOC_DIRS.items():
        top_path = REPO_ROOT / top_dir
        if subdirs is None:
            total = count_loc(top_path)
            rows.append([f"{top_dir} (total)", total])
            grand_total += total
        else:
            dir_total = 0
            for sub in subdirs:
                sub_path = top_path / sub
                n = count_loc(sub_path)
                rows.append([f"{top_dir}/{sub}", n])
                dir_total += n
            rows.append([f"{top_dir} (total)", dir_total])
            grand_total += dir_total

    rows.append(["**Total**", grand_total])
    return header, rows


# --- Data types ---


@dataclass
class HostData:
    host: str
    size_bytes: int = 0
    closure_paths: set[str] = field(default_factory=set)
    system_pkgs: int = 0
    home_pkgs: int = 0
    system_refs: int = 0
    home_refs: int = 0
    error: str | None = None


@dataclass
class TimingStats:
    times: list[float] = field(default_factory=list)

    @property
    def mean(self):
        return statistics.mean(self.times) if self.times else 0.0

    @property
    def median(self):
        return statistics.median(self.times) if self.times else 0.0

    @property
    def stdev(self):
        return statistics.stdev(self.times) if len(self.times) > 1 else 0.0

    @property
    def min(self):
        return min(self.times) if self.times else 0.0

    @property
    def max(self):
        return max(self.times) if self.times else 0.0


# --- Package counting (fastfetch-compatible) ---


def is_valid_nix_pkg(path: str) -> bool:
    is_dir = ISDIR_CACHE.get(path)
    if is_dir is None:
        is_dir = os.path.isdir(path)
        ISDIR_CACHE[path] = is_dir
    if not is_dir:
        return False
    base = path.rsplit("/", 1)[-1]
    if base.startswith("nixos-system-nixos-") or base.endswith(
        ("-doc", "-man", "-info", "-dev", "-bin")
    ):
        return False
    return bool(VERSION_RE.search(base))


def count_pkgs_and_refs(paths: list[str]) -> tuple[int, int]:
    pkgs = sum(1 for p in paths if is_valid_nix_pkg(p))
    return pkgs, len(paths)


def requisites(drv: str) -> list[str]:
    r = run(["nix-store", "-q", "--requisites", drv])
    return (
        r.stdout.strip().split("\n") if r.returncode == 0 and r.stdout.strip() else []
    )


# --- Build & measure ---


def build_host(host: str) -> HostData:
    try:
        r = run(
            [
                "nix",
                "build",
                f"path:.#nixosConfigurations.{host}.config.system.build.toplevel",
                "--no-link",
                "--print-out-paths",
            ]
        )
        if r.returncode != 0:
            return HostData(host=host, error=r.stderr.strip() or "Build failed")

        drv = r.stdout.strip()

        sr = run(["nix", "path-info", "--closure-size", drv])
        if sr.returncode != 0:
            return HostData(host=host, error="closure-size failed")
        size_bytes = int(sr.stdout.strip().split()[1])

        cr = run(["nix", "path-info", "--recursive", drv])
        if cr.returncode != 0:
            return HostData(
                host=host, size_bytes=size_bytes, error="closure-paths failed"
            )
        closure_paths = set(cr.stdout.strip().split("\n"))

        sys_pkgs, sys_refs = count_pkgs_and_refs(requisites(drv))

        home_pkgs, home_refs = 0, 0
        users_json = nix_eval(
            f"nixosConfigurations.{host}.config.home-manager.users",
            apply="builtins.attrNames",
        )
        for user in json.loads(users_json) if users_json else []:
            hp = nix_eval(
                f"nixosConfigurations.{host}.config.home-manager.users.{user}.home.path",
                raw=True,
            )
            if hp:
                pk, rf = count_pkgs_and_refs(requisites(hp))
                home_pkgs += pk
                home_refs += rf

        return HostData(
            host=host,
            size_bytes=size_bytes,
            closure_paths=closure_paths,
            system_pkgs=sys_pkgs,
            home_pkgs=home_pkgs,
            system_refs=sys_refs,
            home_refs=home_refs,
        )
    except Exception as e:
        return HostData(host=host, error=str(e))


def eval_host(host: str) -> float:
    start = time.perf_counter()
    r = run(
        [
            "nix",
            "eval",
            f"path:.#nixosConfigurations.{host}.config.system.build.toplevel.drvPath",
            *EVAL_NO_CACHE,
        ]
    )
    elapsed = time.perf_counter() - start
    if r.returncode != 0:
        raise RuntimeError(f"Eval failed for {host}: {r.stderr.strip()}")
    return elapsed


def eval_hosts(hosts: list[str], runs: int, parallel: bool) -> dict[str, TimingStats]:
    timing: dict[str, TimingStats] = {h: TimingStats() for h in hosts}
    mode = "Simultaneous" if parallel else "Sequential"
    for run_num in range(1, runs + 1):
        print(f"  {mode} run {run_num}/{runs}", file=sys.stderr)
        if parallel:
            with ThreadPoolExecutor(max_workers=len(hosts)) as executor:
                futures = {executor.submit(eval_host, h): h for h in hosts}
                for future in as_completed(futures):
                    host = futures[future]
                    elapsed = future.result()
                    timing[host].times.append(elapsed)
                    print(f"    ✓ {host}: {elapsed:.2f}s", file=sys.stderr)
        else:
            for host in hosts:
                elapsed = eval_host(host)
                timing[host].times.append(elapsed)
                print(f"    ✓ {host}: {elapsed:.2f}s", file=sys.stderr)
    return timing


# --- Markdown output ---


def fmt_size(b: int) -> str:
    return f"{b / (1024**3):.2f} GiB"


def v_or_dash(n: int) -> str:
    return str(n) if n > 0 else "-"


def build_markdown(
    host_data: dict[str, HostData],
    seq: dict[str, TimingStats],
    sim: dict[str, TimingStats],
    hosts: list[str],
    nix_version: str,
    git_hash: str,
    cpu_model: str,
    disk_info: str,
    memory: str,
    runs: int,
) -> str:
    parts: list[str] = []

    # Common header
    parts.append(f"""
commit hash: {git_hash}

{nix_version}

CPU: {cpu_model}

Disk: {disk_info}

Memory: {memory}
""")

    # --- LOC table ---
    loc_header, loc_rows = build_loc_table()
    parts.append(loc_header)
    parts.append(
        tabulate(
            loc_rows,
            headers=["Component", "Lines"],
            tablefmt="pipe",
            stralign="left",
            numalign="right",
        )
    )

    # --- Size table ---
    parts.append("""
## NixOS Configuration Sizes

**Table 2:** NixOS system configuration sizes for each host.

This table presents the closure size (total disk space required for all dependencies)
for each configured host in the infrastructure. Closure size is measured in GiB
(gibibytes, 2³⁰ bytes) and represents the complete set of packages, libraries,
and system components required for each configuration. System/Home Pkgs shows
the count of packages in each profile (excluding -doc, -man, -info, -dev, -bin outputs).
System/Home Refs shows the total recursive dependencies for each profile.
""")
    rows = []
    for h in hosts:
        d = host_data[h]
        if d.error:
            rows.append([h, "ERROR", "ERROR", "ERROR", "ERROR", "ERROR"])
        else:
            rows.append(
                [
                    h,
                    fmt_size(d.size_bytes),
                    v_or_dash(d.system_pkgs),
                    v_or_dash(d.home_pkgs),
                    v_or_dash(d.system_refs),
                    v_or_dash(d.home_refs),
                ]
            )
    parts.append(
        tabulate(
            rows,
            headers=[
                "Host",
                "Closure Size",
                "System Pkgs",
                "Home Pkgs",
                "System Refs",
                "Home Refs",
            ],
            tablefmt="pipe",
            stralign="right",
            numalign="right",
        )
    )

    # --- Eval performance ---
    parts.append(f"""
## Eval Performance

**Statistics computed over {runs} run(s)**""")

    for i, (mode, stats, label) in enumerate(
        [
            (
                "Sequential",
                seq,
                "Evaluation time per host with no concurrent evaluation.\n\nEach host is evaluated in isolation using `nix eval --option eval-cache false` to ensure deterministic, cache-free measurements.",
            ),
            (
                "Simultaneous",
                sim,
                "Evaluation time per host with all hosts evaluated concurrently.\n\nAll hosts are evaluated in parallel to measure the overhead of concurrent Nix evaluation (CPU contention, lock contention, etc.).",
            ),
        ],
        start=3,
    ):
        parts.append(f"""
### {mode}

**Table {i}:** {label}
""")
        rows = [
            [
                h,
                f"{stats[h].mean:.3f}s",
                f"{stats[h].median:.3f}s",
                f"{stats[h].stdev:.3f}s",
                f"{stats[h].min:.3f}s",
                f"{stats[h].max:.3f}s",
                len(stats[h].times),
            ]
            for h in hosts
            if stats[h].times
        ]
        parts.append(
            tabulate(
                rows,
                headers=["Host", "Mean", "Median", "Std Dev", "Min", "Max", "Runs"],
                tablefmt="pipe",
                stralign="right",
                numalign="right",
            )
        )

    # --- Reuse matrix ---
    parts.append("""
## Closure Reuse Matrix

**Table 5:** Binary-level dependency sharing between host configurations.

This matrix quantifies the degree of dependency reuse across different NixOS host
configurations. Each cell shows the percentage of packages (derivations) from the
row host's closure that also appear in the column host's closure. A value of 100%
would indicate complete subsumption. The diagonal shows dashes (-) as self-comparison
is omitted. Higher percentages indicate greater infrastructure consolidation potential
through shared package caches and common dependency management.
""")
    rows = []
    for h1 in hosts:
        d1 = host_data[h1]
        if d1.error:
            continue
        total = len(d1.closure_paths)
        row = [h1]
        for h2 in hosts:
            d2 = host_data[h2]
            if d2.error:
                row.append("ERR")
            elif h1 == h2:
                row.append("-")
            else:
                shared = len(d1.closure_paths & d2.closure_paths)
                row.append(f"{int(shared * 100 / total) if total else 0}%")
        rows.append(row)
    parts.append(
        tabulate(
            rows,
            headers=["Host"] + hosts,
            tablefmt="pipe",
            stralign="right",
            numalign="right",
        )
    )

    return "\n".join(parts)


# --- Graph generation ---


def make_eval_chart(
    stats: dict[str, TimingStats], hosts: list[str], title: str, color: str, path: Path
):
    means = [stats[h].mean for h in hosts]
    stdevs = [stats[h].stdev for h in hosts]
    x = np.arange(len(hosts))

    _, ax = plt.subplots(figsize=(max(10, len(hosts) * 0.8), 6))
    bars = ax.bar(
        x,
        means,
        yerr=stdevs,
        capsize=4,
        color=color,
        edgecolor="black",
        linewidth=0.5,
        error_kw={"linewidth": 1.5, "capthick": 1.5},
    )

    ax.set_xlabel("Host", fontsize=12, fontweight="bold")
    ax.set_ylabel("Evaluation Time (seconds)", fontsize=12, fontweight="bold")
    ax.set_title(title, fontsize=14, fontweight="bold")
    ax.set_xticks(x)
    ax.set_xticklabels(hosts, rotation=45, ha="right")
    ax.yaxis.grid(True, linestyle="--", alpha=0.7)
    ax.set_axisbelow(True)
    ax.set_ylim(0, max(m + s for m, s in zip(means, stdevs)) * 1.15 or 1)

    for i, (bar, mean) in enumerate(zip(bars, means)):
        ax.annotate(
            f"{mean:.2f}s",
            xy=(bar.get_x() + bar.get_width() / 2, bar.get_height() + stdevs[i]),
            xytext=(0, 5),
            textcoords="offset points",
            ha="center",
            va="bottom",
            fontsize=9,
        )

    plt.tight_layout()
    plt.savefig(path, dpi=150, bbox_inches="tight")
    plt.close()
    print(f"✓ Generated {path}", file=sys.stderr)


# --- File I/O ---


def update_readme(content: str):
    if not README_PATH.exists():
        print("⚠ README.md not found", file=sys.stderr)
        return
    text = README_PATH.read_text()
    s, e = text.find(STATS_START), text.find(STATS_END)
    if s == -1 or e == -1:
        print("⚠ Stats markers not found in README.md", file=sys.stderr)
        return
    README_PATH.write_text(text[: s + len(STATS_START)] + "\n" + content + text[e:])
    print("✓ Updated README.md", file=sys.stderr)


def save_file(content: str, subdir: str, filename: str):
    d = Path(subdir)
    d.mkdir(parents=True, exist_ok=True)
    p = d / filename
    p.write_text(content)
    print(f"✓ Saved {p}", file=sys.stderr)


# --- Main ---


def main():
    parser = argparse.ArgumentParser(
        description="NixOS Configuration Statistics Generator"
    )
    parser.add_argument(
        "--runs", type=int, default=3, help="Eval runs per mode (default: 3)"
    )
    parser.add_argument(
        "--hosts", nargs="+", default=None, help="Specific hosts (default: all)"
    )
    args = parser.parse_args()

    nix_version = run(["nix", "--version"]).stdout.strip() or "unknown"
    git_hash = get_git_hash()
    cpu_model = get_cpu_model()
    disk_info = get_disk_info()
    memory = get_memory()
    print(f"Fetching hosts... ({nix_version} · {git_hash})", file=sys.stderr)

    all_hosts = sorted(
        json.loads(nix_eval("nixosConfigurations", apply="builtins.attrNames"))
    )
    hosts = args.hosts or all_hosts
    if args.hosts:
        invalid = set(args.hosts) - set(all_hosts)
        if invalid:
            print(f"❌ Unknown hosts: {', '.join(invalid)}", file=sys.stderr)
            sys.exit(1)
    if not hosts:
        print("❌ No hosts found", file=sys.stderr)
        sys.exit(1)
    print(f"Hosts ({len(hosts)}): {', '.join(hosts)}", file=sys.stderr)

    # 1. Build hosts (parallel) for size/closure data
    print("\nBuilding hosts...", file=sys.stderr)
    host_data: dict[str, HostData] = {}
    with ThreadPoolExecutor(max_workers=len(hosts)) as executor:
        futures = {executor.submit(build_host, h): h for h in hosts}
        for future in as_completed(futures):
            host = futures[future]
            result = future.result()
            if result.error:
                print(f"  ❌ {host}: {result.error}", file=sys.stderr)
                sys.exit(1)
            host_data[host] = result
            print(f"  ✓ {host}: {fmt_size(result.size_bytes)}", file=sys.stderr)

    # 2. Eval benchmarks
    print(f"\nRunning {args.runs} eval benchmark(s) per mode...", file=sys.stderr)
    print("\nSequential eval:", file=sys.stderr)
    seq = eval_hosts(hosts, args.runs, parallel=False)
    print("\nSimultaneous eval:", file=sys.stderr)
    sim = eval_hosts(hosts, args.runs, parallel=True)

    # 3. Generate graphs
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    subdir = f"generated/flake-stats_{ts}"
    out = Path(subdir)
    out.mkdir(parents=True, exist_ok=True)
    make_eval_chart(
        seq,
        hosts,
        "NixOS Eval Time — Sequential\n(Mean ± Std Dev)",
        "#2196F3",
        out / "eval_sequential.png",
    )
    make_eval_chart(
        sim,
        hosts,
        "NixOS Eval Time — Simultaneous\n(Mean ± Std Dev)",
        "#4CAF50",
        out / "eval_simultaneous.png",
    )

    # 4. Markdown output
    md = build_markdown(host_data, seq, sim, hosts, nix_version, git_hash, cpu_model, disk_info, memory, args.runs)
    print(md, end="")

    # 5. Save
    update_readme(md)
    save_file(md, subdir, "statistics.md")


if __name__ == "__main__":
    main()

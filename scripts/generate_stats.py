#!/usr/bin/env python3
"""
NixOS Configuration Statistics Generator

Builds all hosts in parallel, measures eval time and closure size,
and computes closure reuse percentages between hosts.

Outputs markdown tables suitable for thesis/README.

Usage:
    task generate                    # Single run
    task generate -- --runs 5        # 5 runs for averaging
"""

import subprocess
import json
import time
import sys
import os
import re
import threading
import argparse
import statistics
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Dict, List, Set, Optional, Tuple
from dataclasses import dataclass, field
from datetime import datetime
from tabulate import tabulate
from io import StringIO

README_PATH = Path(__file__).parent.parent / "README.md"
GENERATED_DIR = Path(__file__).parent.parent / "generated"
STATS_START_MARKER = "<!-- STATS_START -->"
STATS_END_MARKER = "<!-- STATS_END -->"

VERSION_PATTERN = re.compile(r"-\d+\.\d+")
ISDIR_CACHE: Dict[str, bool] = {}


@dataclass
class BuildResult:
    host: str
    derivation: str
    size_bytes: int
    elapsed_seconds: float
    closure_paths: Set[str]
    system_pkgs: int = 0
    home_pkgs: int = 0
    system_refs: int = 0
    home_refs: int = 0
    error: Optional[str] = None


@dataclass
class TimingStats:
    host: str
    times: List[float] = field(default_factory=list)

    @property
    def mean(self) -> float:
        return statistics.mean(self.times) if self.times else 0.0

    @property
    def median(self) -> float:
        return statistics.median(self.times) if self.times else 0.0

    @property
    def stdev(self) -> float:
        return statistics.stdev(self.times) if len(self.times) > 1 else 0.0

    @property
    def min(self) -> float:
        return min(self.times) if self.times else 0.0

    @property
    def max(self) -> float:
        return max(self.times) if self.times else 0.0


def get_hosts(repo_root: Path) -> List[str]:
    """Get sorted list of NixOS configuration hostnames."""
    result = subprocess.run(
        [
            "nix",
            "eval",
            "--json",
            "path:.#nixosConfigurations",
            "--apply",
            "builtins.attrNames",
        ],
        capture_output=True,
        text=True,
        cwd=repo_root,
    )
    if result.returncode != 0:
        raise RuntimeError(f"Failed to get hosts: {result.stderr}")
    return sorted(json.loads(result.stdout))


def is_valid_nix_pkg(path: str) -> bool:
    """Check if a nix store path is a valid package (matches fastfetch logic)."""
    is_dir = ISDIR_CACHE.get(path)
    if is_dir is None:
        is_dir = os.path.isdir(path)
        ISDIR_CACHE[path] = is_dir

    if not is_dir:
        return False

    basename = path.rsplit("/", 1)[-1]

    if basename.startswith("nixos-system-nixos-"):
        return False
    if basename.endswith(("-doc", "-man", "-info", "-dev", "-bin")):
        return False

    return bool(VERSION_PATTERN.search(basename))


def count_nix_packages(paths: List[str]) -> int:
    """Count valid nix packages from a list of store paths."""
    return sum(1 for p in paths if is_valid_nix_pkg(p))


def get_system_packages(toplevel_drv: str) -> Tuple[int, int]:
    """Get system package count and recursive reference count from toplevel."""
    result = subprocess.run(
        ["nix-store", "-q", "--requisites", toplevel_drv],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return 0, 0

    paths = result.stdout.strip().split("\n")
    return count_nix_packages(paths), len(paths)


def get_home_users(host: str, repo_root: Path) -> List[str]:
    """Get list of home-manager users for a host."""
    result = subprocess.run(
        [
            "nix",
            "eval",
            "--json",
            f"path:.#nixosConfigurations.{host}.config.home-manager.users",
            "--apply",
            "builtins.attrNames",
        ],
        capture_output=True,
        text=True,
        cwd=repo_root,
    )
    return json.loads(result.stdout) if result.returncode == 0 else []


def get_home_packages(host: str, user: str, repo_root: Path) -> Tuple[int, int]:
    """Get home package count and recursive reference count for user."""
    path_result = subprocess.run(
        [
            "nix",
            "eval",
            "--raw",
            f"path:.#nixosConfigurations.{host}.config.home-manager.users.{user}.home.path",
        ],
        capture_output=True,
        text=True,
        cwd=repo_root,
    )
    if path_result.returncode != 0:
        return 0, 0

    reqs_result = subprocess.run(
        ["nix-store", "-q", "--requisites", path_result.stdout.strip()],
        capture_output=True,
        text=True,
    )
    if reqs_result.returncode != 0:
        return 0, 0

    paths = reqs_result.stdout.strip().split("\n")
    return count_nix_packages(paths), len(paths)


def build_host(host: str, repo_root: Path) -> BuildResult:
    """Build a single host and collect metrics."""
    start = time.perf_counter()

    try:
        build_result = subprocess.run(
            [
                "nix",
                "build",
                f"path:.#nixosConfigurations.{host}.config.system.build.toplevel",
                "--no-link",
                "--print-out-paths",
            ],
            capture_output=True,
            text=True,
            cwd=repo_root,
        )

        if build_result.returncode != 0:
            return BuildResult(
                host=host,
                derivation="",
                size_bytes=0,
                elapsed_seconds=0,
                closure_paths=set(),
                error=build_result.stderr.strip() or "Build failed",
            )

        drv = build_result.stdout.strip()
        elapsed = time.perf_counter() - start

        size_result = subprocess.run(
            ["nix", "path-info", "--closure-size", drv], capture_output=True, text=True
        )
        if size_result.returncode != 0:
            return BuildResult(
                host=host,
                derivation=drv,
                size_bytes=0,
                elapsed_seconds=elapsed,
                closure_paths=set(),
                error="Failed to get closure size",
            )

        size_bytes = int(size_result.stdout.strip().split()[1])

        closure_result = subprocess.run(
            ["nix", "path-info", "--recursive", drv], capture_output=True, text=True
        )
        if closure_result.returncode != 0:
            return BuildResult(
                host=host,
                derivation=drv,
                size_bytes=size_bytes,
                elapsed_seconds=elapsed,
                closure_paths=set(),
                error="Failed to get closure paths",
            )

        closure_paths = set(closure_result.stdout.strip().split("\n"))
        system_pkgs, system_refs = get_system_packages(drv)

        home_pkgs, home_refs = 0, 0
        for user in get_home_users(host, repo_root):
            pkg_count, ref_count = get_home_packages(host, user, repo_root)
            home_pkgs += pkg_count
            home_refs += ref_count

        return BuildResult(
            host=host,
            derivation=drv,
            size_bytes=size_bytes,
            elapsed_seconds=elapsed,
            closure_paths=closure_paths,
            system_pkgs=system_pkgs,
            home_pkgs=home_pkgs,
            system_refs=system_refs,
            home_refs=home_refs,
        )

    except Exception as e:
        return BuildResult(
            host=host,
            derivation="",
            size_bytes=0,
            elapsed_seconds=0,
            closure_paths=set(),
            error=str(e),
        )


def format_size(size_bytes: int) -> str:
    """Format bytes as GiB."""
    return f"{size_bytes / (1024**3):.2f} GiB"


def format_time(seconds: float) -> str:
    """Format seconds as SS.XXs."""
    return f"{seconds:.2f}s"


def get_cpu_percent() -> float:
    """Read CPU usage from /proc/stat (Linux only)."""
    try:
        with open("/proc/stat") as f:
            parts = f.readline().split()
        user, nice, system, idle, iowait = (
            int(parts[1]),
            int(parts[2]),
            int(parts[3]),
            int(parts[4]),
            int(parts[5]),
        )
        irq, softirq, steal = int(parts[6]), int(parts[7]), int(parts[8])
        active = user + nice + system + irq + softirq + steal
        return (
            (active / (active + idle + iowait)) * 100
            if (active + idle + iowait) > 0
            else 0
        )
    except:
        return 0


def cpu_monitor_thread(interval: float, stop_event: threading.Event):
    """Background thread to monitor CPU and warn if > 95%."""
    while not stop_event.is_set():
        cpu = get_cpu_percent()
        if cpu > 95:
            print(f"⚠ Warning: CPU usage at {cpu:.1f}%", file=sys.stderr)
        time.sleep(interval)


def print_size_table(
    results: Dict[str, BuildResult],
    hosts: List[str],
    timing_stats: Optional[Dict[str, TimingStats]] = None,
):
    """Print markdown table of sizes and build times."""
    print("\n## NixOS Configuration Sizes\n")
    print(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M')}\n")

    if timing_stats:
        print(
            f"**Statistics computed over {len(next(iter(timing_stats.values())).times)} build run(s)**\n"
        )

    print(
        "**Table 1:** NixOS system configuration sizes and evaluation times for each host."
    )
    print(
        "\nThis table presents the closure size (total disk space required for all dependencies)"
    )
    print(
        "and evaluation time (time to compute the Nix derivation) for each configured host"
    )
    print(
        "in the infrastructure. Closure size is measured in GiB (gibibytes, 2³⁰ bytes)"
    )
    print(
        "and represents the complete set of packages, libraries, and system components"
    )
    print(
        "required for each configuration. System/Home Pkgs shows the count of packages"
    )
    print("in each profile (excluding -doc, -man, -info, -dev, -bin outputs).")
    print("System/Home Refs shows the total recursive dependencies for each profile.")
    print("Evaluation time measures the computational overhead of the Nix")
    print(
        "expression evaluator and is performed on cached derivations, representing the"
    )
    print("minimal overhead when no packages need rebuilding.\n")

    table_data = []
    for host in hosts:
        result = results[host]
        if result.error:
            row = [host, "ERROR", "ERROR", "ERROR", "ERROR", "ERROR", "ERROR"]
        else:
            time_str = (
                f"{format_time(timing_stats[host].mean)} ± {format_time(timing_stats[host].stdev)}"
                if timing_stats
                else format_time(result.elapsed_seconds)
            )
            row = [
                host,
                format_size(result.size_bytes),
                str(result.system_pkgs) if result.system_pkgs > 0 else "-",
                str(result.home_pkgs) if result.home_pkgs > 0 else "-",
                str(result.system_refs) if result.system_refs > 0 else "-",
                str(result.home_refs) if result.home_refs > 0 else "-",
                time_str,
            ]
        table_data.append(row)

    print(
        tabulate(
            table_data,
            headers=[
                "Host",
                "Closure Size",
                "System Pkgs",
                "Home Pkgs",
                "System Refs",
                "Home Refs",
                "Eval Time",
            ],
            tablefmt="pipe",
            stralign="right",
            numalign="right",
        )
    )


def print_timing_statistics(
    timing_stats: Dict[str, TimingStats],
    hosts: List[str],
    subdir: str,
    bar_path: str = "",
    box_path: str = "",
):
    """Print detailed timing statistics table."""
    print("\n## Timing Statistics\n")
    print("**Table 3:** Detailed timing statistics across multiple runs.\n")

    table_data = [
        [
            h,
            f"{timing_stats[h].mean:.3f}s",
            f"{timing_stats[h].median:.3f}s",
            f"{timing_stats[h].stdev:.3f}s",
            f"{timing_stats[h].min:.3f}s",
            f"{timing_stats[h].max:.3f}s",
            len(timing_stats[h].times),
        ]
        for h in hosts
        if h in timing_stats and timing_stats[h].times
    ]

    if table_data:
        print(
            tabulate(
                table_data,
                headers=["Host", "Mean", "Median", "Std Dev", "Min", "Max", "Runs"],
                tablefmt="pipe",
                stralign="right",
                numalign="right",
            )
        )

    if bar_path or box_path:
        print("\n### Visualizations\n")
        if bar_path:
            print(f"- ![Bar Chart]({subdir}/{Path(bar_path).name})")
        if box_path:
            print(f"- ![Box Plot]({subdir}/{Path(box_path).name})")


def print_reuse_matrix(results: Dict[str, BuildResult], hosts: List[str]):
    """Print markdown matrix of closure reuse percentages."""
    print("\n## Closure Reuse Matrix\n")

    print("**Table 2:** Binary-level dependency sharing between host configurations.")
    print(
        "\nThis matrix quantifies the degree of dependency reuse across different NixOS host"
    )
    print(
        "configurations. Each cell shows the percentage of packages (derivations) from the"
    )
    print(
        "row host's closure that also appear in the column host's closure. A value of 100%"
    )
    print(
        "would indicate complete subsumption (all packages from row host are present in column"
    )
    print(
        "host). The diagonal shows dashes (-) as self-comparison is omitted. Higher percentages"
    )
    print(
        "indicate greater infrastructure consolidation potential through shared package caches"
    )
    print(
        "and common dependency management. This metric is particularly relevant for optimizing"
    )
    print(
        "distributed builds, reducing network transfer overhead, and minimizing storage"
    )
    print("requirements in multi-host deployments.\n")

    table_data = []
    for host1 in hosts:
        result1 = results[host1]
        if result1.error:
            continue

        closure1, total = result1.closure_paths, len(result1.closure_paths)
        row = [host1]
        for host2 in hosts:
            result2 = results[host2]
            if result2.error:
                row.append("ERR")
            elif host1 == host2:
                row.append("-")
            else:
                shared = len(closure1 & result2.closure_paths)
                row.append(f"{int(shared * 100 / total) if total > 0 else 0}%")
        table_data.append(row)

    print(
        tabulate(
            table_data,
            headers=["Host"] + hosts,
            tablefmt="pipe",
            stralign="right",
            numalign="right",
        )
    )


def update_readme(content: str):
    """Update the statistics section in README.md."""
    if not README_PATH.exists():
        print(f"⚠ README.md not found at {README_PATH}", file=sys.stderr)
        return

    readme_content = README_PATH.read_text()
    start_idx, end_idx = (
        readme_content.find(STATS_START_MARKER),
        readme_content.find(STATS_END_MARKER),
    )

    if start_idx == -1 or end_idx == -1:
        print("⚠ Could not find stats markers in README.md", file=sys.stderr)
        return

    README_PATH.write_text(
        readme_content[: start_idx + len(STATS_START_MARKER)]
        + "\n"
        + content
        + readme_content[end_idx:]
    )
    print("✓ Updated README.md", file=sys.stderr)


def save_generated(content: str, subdir: str, filename: str):
    """Save content to the generated directory in a timestamped subfolder."""
    output_dir = Path(subdir)
    output_dir.mkdir(parents=True, exist_ok=True)
    filepath = output_dir / filename
    filepath.write_text(content)
    print(f"✓ Saved {filepath}", file=sys.stderr)
    return filepath


def generate_graphs(
    timing_data: Dict[str, TimingStats], hosts: List[str], subdir: str
) -> Tuple[str, str]:
    """Generate bar chart and box plot visualizations. Returns (bar_path, box_path)."""
    output_dir = Path(subdir)
    output_dir.mkdir(parents=True, exist_ok=True)

    mean_times = [timing_data[h].mean for h in hosts]
    stdev_times = [timing_data[h].stdev for h in hosts]
    host_indices = np.arange(len(hosts))

    fig, ax = plt.subplots(figsize=(max(10, len(hosts) * 0.8), 6))
    bars = ax.bar(
        host_indices,
        mean_times,
        yerr=stdev_times,
        capsize=4,
        color="#2196F3",
        edgecolor="black",
        linewidth=0.5,
        error_kw={"linewidth": 1.5, "capthick": 1.5},
    )

    ax.set_xlabel("Host", fontsize=12, fontweight="bold")
    ax.set_ylabel("Evaluation Time (seconds)", fontsize=12, fontweight="bold")
    ax.set_title(
        "NixOS Configuration Evaluation Times\n(Mean ± Std Dev)",
        fontsize=14,
        fontweight="bold",
    )
    ax.set_xticks(host_indices)
    ax.set_xticklabels(hosts, rotation=45, ha="right")
    ax.yaxis.grid(True, linestyle="--", alpha=0.7)
    ax.set_axisbelow(True)
    ax.set_ylim(0, max(m + s for m, s in zip(mean_times, stdev_times)) * 1.15)

    for i, (bar, mean) in enumerate(zip(bars, mean_times)):
        ax.annotate(
            f"{mean:.2f}s",
            xy=(bar.get_x() + bar.get_width() / 2, bar.get_height() + stdev_times[i]),
            xytext=(0, 5),
            textcoords="offset points",
            ha="center",
            va="bottom",
            fontsize=9,
        )

    plt.tight_layout()
    bar_path = output_dir / "infrastructure-configurations_timing_barchart.png"
    plt.savefig(bar_path, dpi=150, bbox_inches="tight")
    plt.close()
    print(f"✓ Generated {bar_path}", file=sys.stderr)

    fig, ax = plt.subplots(figsize=(max(10, len(hosts) * 0.8), 6))
    bp = ax.boxplot(
        [timing_data[h].times for h in hosts], patch_artist=True, labels=hosts
    )
    for patch in bp["boxes"]:
        patch.set_facecolor("#4CAF50")
        patch.set_alpha(0.7)

    ax.set_xlabel("Host", fontsize=12, fontweight="bold")
    ax.set_ylabel("Evaluation Time (seconds)", fontsize=12, fontweight="bold")
    ax.set_title(
        "NixOS Configuration Evaluation Time Distribution\n(Box Plot: Min, Q1, Median, Q3, Max)",
        fontsize=14,
        fontweight="bold",
    )
    ax.yaxis.grid(True, linestyle="--", alpha=0.7)
    ax.set_axisbelow(True)
    plt.xticks(rotation=45, ha="right")

    plt.tight_layout()
    box_path = output_dir / "infrastructure-configurations_timing_boxplot.png"
    plt.savefig(box_path, dpi=150, bbox_inches="tight")
    plt.close()
    print(f"✓ Generated {box_path}", file=sys.stderr)

    return str(bar_path), str(box_path)


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="NixOS Configuration Statistics Generator"
    )
    parser.add_argument(
        "--runs",
        type=int,
        default=1,
        help="Number of build runs to perform (for averaging timing statistics)",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).parent.parent

    print("Fetching hosts...", file=sys.stderr)
    hosts = get_hosts(repo_root)

    if not hosts:
        print("❌ No hosts found", file=sys.stderr)
        sys.exit(1)

    print(f"Found {len(hosts)} hosts: {', '.join(hosts)}", file=sys.stderr)

    timing_data: Dict[str, TimingStats] = {h: TimingStats(host=h) for h in hosts}
    last_results: Dict[str, BuildResult] = {}

    for run_num in range(1, args.runs + 1):
        if args.runs > 1:
            print(f"\n=== Run {run_num}/{args.runs} ===\n", file=sys.stderr)

        stop_monitor = threading.Event()
        monitor = threading.Thread(target=cpu_monitor_thread, args=(2.0, stop_monitor))
        monitor.daemon = True
        monitor.start()

        results: Dict[str, BuildResult] = {}

        try:
            print(
                f"Building {len(hosts)} hosts with {len(hosts)} workers...\n",
                file=sys.stderr,
            )

            with ThreadPoolExecutor(max_workers=len(hosts)) as executor:
                futures = {executor.submit(build_host, h, repo_root): h for h in hosts}

                for future in as_completed(futures):
                    host = futures[future]
                    try:
                        result = future.result()

                        if result.error:
                            print(
                                f"\n❌ Build failed for {host}: {result.error}",
                                file=sys.stderr,
                            )
                            executor.shutdown(wait=False, cancel_futures=True)
                            sys.exit(1)

                        results[host] = result
                        timing_data[host].times.append(result.elapsed_seconds)
                        print(
                            f"  ✓ {host}: {format_time(result.elapsed_seconds)}",
                            file=sys.stderr,
                        )

                    except Exception as e:
                        print(f"\n❌ Exception for {host}: {e}", file=sys.stderr)
                        executor.shutdown(wait=False, cancel_futures=True)
                        sys.exit(1)

        finally:
            stop_monitor.set()
            monitor.join(timeout=1)

        last_results = results

    output = StringIO()
    original_stdout = sys.stdout

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    subdir = f"generated/stats_{timestamp}"

    bar_path, box_path = ("", "")
    if args.runs > 1:
        bar_path, box_path = generate_graphs(timing_data, hosts, subdir)

    sys.stdout = original_stdout
    print_size_table(last_results, hosts, timing_data if args.runs > 1 else None)
    if args.runs > 1:
        print_timing_statistics(timing_data, hosts, subdir, bar_path, box_path)
    print_reuse_matrix(last_results, hosts)

    sys.stdout = output
    print_size_table(last_results, hosts, timing_data if args.runs > 1 else None)
    if args.runs > 1:
        print_timing_statistics(timing_data, hosts, subdir, bar_path, box_path)
    print_reuse_matrix(last_results, hosts)
    sys.stdout = original_stdout

    update_readme(output.getvalue())
    save_generated(
        output.getvalue(), subdir, "infrastructure-confogurations-statistics.md"
    )


if __name__ == "__main__":
    main()

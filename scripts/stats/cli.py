"""CLI orchestration for the stats pipeline.

Fast tier (default): LOC only, then the fast README region, the LOC chart and
generated/ retention. Runs from the pre-commit hook on every commit.

Heavy tier (``--heavy``): its own host-facts eval, parallel closure builds and
reuse, then the heavy README region, the three heavy charts and retention.
Manual, budgeted under 5 minutes.

Both tiers time every stage and print the table on stderr. ``--dry-run``
collects and prints the tier block without writing README.md or assets/stats/
and without pruning generated/.
"""

from __future__ import annotations

import argparse
import sys
from datetime import datetime, timezone

from . import charts, pipeline, render
from .pipeline import (
    FAST_END,
    FAST_START,
    GENERATED_DIR,
    HEAVY_END,
    HEAVY_START,
    RUN_PREFIXES,
    Measurements,
)
from .util import Stage, Timing, prune_runs

DEFAULT_KEEP = 5

DRY_RUN_NOTE = "Dry run: skipped README.md, assets/stats/ and retention"


def _log(message: str) -> None:
    print(message, file=sys.stderr)


def _iso(moment: datetime) -> str:
    return moment.isoformat(timespec="seconds").replace("+00:00", "Z")


def _update_region(block: str, start: str, end: str, label: str) -> None:
    if render.update_readme(block, start, end):
        _log(f"Updated README.md {label} block")
    elif render.missing_markers(render.README_PATH, start, end):
        _log(f"warning: {label.upper()} markers not found in README.md, block not written")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="NixOS Configuration Statistics")
    parser.add_argument("--heavy", action="store_true",
                        help="run the heavy tier (closures and reuse)")
    parser.add_argument("--hosts", nargs="+", default=None,
                        help="heavy tier: nixosConfigurations to measure (default: all)")
    parser.add_argument("--keep", type=int, default=DEFAULT_KEEP,
                        help="generated/ run directories to keep per family; "
                             "0 deletes all run archives (default: 5)")
    parser.add_argument("--dry-run", action="store_true",
                        help="collect and print without writing README.md or assets/**")
    return parser


def _publish(timing: Timing, keep: int, render_charts) -> None:
    with timing.stage(Stage.CHARTS):
        for chart_path in render_charts():
            _log(f"Wrote {chart_path}")
    with timing.stage(Stage.RETENTION):
        for pruned in prune_runs(GENERATED_DIR, RUN_PREFIXES, keep):
            _log(f"Pruned {pruned}")


def _run_fast(args: argparse.Namespace, timing: Timing, dry_run: bool) -> int:
    with timing.stage(Stage.LOC):
        entries = pipeline.build_loc_entries(pipeline.REPO_ROOT)
    with timing.stage(Stage.RENDER):
        block = render.render_fast_block(entries)
        if not dry_run:
            _update_region(block, FAST_START, FAST_END, "fast")
    if dry_run:
        print(block)
        _log(DRY_RUN_NOTE)
        return 0
    _publish(timing, args.keep, lambda: charts.render_fast_charts(entries))
    print(block)
    return 0


def _run_heavy(args: argparse.Namespace, timing: Timing, dry_run: bool) -> int:
    measured_at = _iso(datetime.now(timezone.utc))

    _log("Evaluating host matrix...")
    with timing.stage(Stage.HOST_MATRIX):
        all_facts = pipeline.collect_host_matrix()
    if not all_facts:
        _log("error: no nixosConfigurations found (run from the flake checkout)")
        return 1

    if args.hosts:
        hosts = sorted(dict.fromkeys(args.hosts))
        unknown = set(hosts) - set(all_facts)
        if unknown:
            _log(f"error: unknown hosts: {', '.join(sorted(unknown))}")
            return 1
        if len(hosts) < len(all_facts) and not dry_run:
            _log("error: refusing to publish a partial fleet measurement; "
                 "drop --hosts or use --dry-run")
            return 1
    else:
        hosts = sorted(all_facts)
    facts = {host: all_facts[host] for host in hosts}
    _log(f"Hosts ({len(hosts)}): {', '.join(hosts)}")

    _log("Building hosts and measuring closures...")
    closures, host_paths = pipeline.build_closures(hosts, facts, timing)
    for host, closure in sorted(closures.items()):
        if closure.error:
            _log(f"  error: {host}: {closure.error}")
    if any(closure.error for closure in closures.values()):
        return 1
    for host in hosts:
        _log(f"  {host}: {pipeline.fmt_gib(closures[host].size_bytes)}")

    sizes = {host: closures[host].size_bytes for host in hosts}
    with timing.stage(Stage.CLOSURE_REUSE):
        reuse = pipeline.build_reuse_summary(hosts, host_paths, sizes)
    document = Measurements(measuredAt=measured_at,
                            hostFacts=[facts[host] for host in hosts],
                            closures=closures, reuse=reuse)

    with timing.stage(Stage.RENDER):
        block = render.render_heavy_block(document)
        if not dry_run:
            _update_region(block, HEAVY_START, HEAVY_END, "heavy")
    if dry_run:
        print(block)
        _log(DRY_RUN_NOTE)
        return 0
    _publish(timing, args.keep, lambda: charts.render_heavy_charts(document))
    print(block)
    return 0


def run(args: argparse.Namespace, dry_run: bool = False) -> int:
    """Run the selected tier with a timing collector; always prints the table."""
    timing = Timing()
    try:
        if args.heavy:
            return _run_heavy(args, timing, dry_run)
        return _run_fast(args, timing, dry_run)
    finally:
        print(timing.table(), file=sys.stderr)


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.keep < 0:
        _log("error: --keep must not be negative")
        return 2
    return run(args, dry_run=args.dry_run)

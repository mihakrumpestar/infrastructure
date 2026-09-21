"""README rendering for the two generated regions.

The fast block renders the LOC summary, its table and the LOC chart; the
heavy block renders the Fleet table, the heavy charts, the consolidation line
and the reuse matrix. Tables use ``tabulate`` in pipe format.
"""

from __future__ import annotations

from pathlib import Path

from tabulate import tabulate

from .charts import CHART_EXT
from .pipeline import (
    FAST_CHART_STEMS,
    FAST_END,
    FAST_START,
    HEAVY_CHART_STEMS,
    README_PATH,
    LocEntry,
    Measurements,
    gib,
    loc_leaf_entries,
)
from .util import write_if_changed

#: Chart stems aliased from the tier tuples so a rename cannot desync them.
LOC_CHART, CLOSURE_CHART, PACKAGE_CHART, REUSE_CHART = (
    *FAST_CHART_STEMS,
    *HEAVY_CHART_STEMS,
)


def _text(value: object) -> str:
    return "n/a" if value is None or value == "" else str(value)


def _count(value: int | None) -> str:
    return f"{value:,}" if value is not None else "n/a"


def _percent(value: float) -> str:
    return f"{value:.0f}%"


def _table(rows: list[list[str]], headers: list[str], aligns: tuple[str, ...]) -> str:
    return tabulate(rows, headers=headers, tablefmt="pipe",
                    disable_numparse=True, colalign=aligns)


def render_loc_summary(entries: list[LocEntry]) -> str:
    """One sentence: total non-blank lines."""
    leaves = loc_leaf_entries(entries)
    total = next(
        (entry.lines for entry in entries if entry.component.strip("*") == "Total"),
        None,
    )
    if total is None:
        total = sum(entry.lines for entry in leaves)
    method = "comments included and Markdown excluded"
    return f"{total:,} non-blank lines, {method}."


def render_loc_table(entries: list[LocEntry]) -> str:
    rows = [[entry.component, _count(entry.lines)] for entry in entries]
    return _table(rows, ["Component", "Lines"], ("left", "right"))


def render_host_overview_table(doc: Measurements) -> str:
    """Fleet table; closure and package columns share the chart sources."""
    by_host = {facts.host: facts for facts in doc.hostFacts}
    rows = []
    for host in doc.hosts():
        facts = by_host.get(host)
        closure = doc.closures.get(host)
        failed = closure is None or bool(closure.error)
        home = (
            _count(closure.homePackages)
            if facts and facts.hmUsers and not failed
            else "n/a"
        )
        rows.append([
            host,
            _text(facts.de if facts else None),
            "n/a" if failed else f"{gib(closure.size_bytes):.2f}",
            "n/a" if failed else _count(closure.systemPackages),
            home,
            _count(facts.services) if facts else "n/a",
            _count(facts.ageSecrets) if facts else "n/a",
        ])
    return _table(
        rows,
        ["Host", "Desktop", "Closure (GiB)", "System pkgs", "Home pkgs",
         "Services", "Secrets"],
        ("left", "left", "right", "right", "right", "right", "right"),
    )


def render_consolidation_line(doc: Measurements) -> str:
    reuse = doc.reuse
    return (
        f"Union closure {gib(reuse.unionBytes):.2f} GiB; summing the hosts "
        f"separately gives {gib(reuse.sumBytes):.2f} GiB, so "
        f"{_percent(reuse.savingsPct)} is shared."
    )


def render_reuse_matrix(doc: Measurements) -> str:
    reuse = doc.reuse
    rows = []
    for row_host in reuse.hosts:
        row = [row_host]
        for column_host in reuse.hosts:
            value = reuse.matrix.get(row_host, {}).get(column_host)
            row.append("" if row_host == column_host else
                       "n/a" if value is None else _percent(value))
        rows.append(row)
    return _table(rows, ["Host"] + list(reuse.hosts),
                  ("left",) + ("right",) * len(reuse.hosts))


def render_chart(stem: str, alt: str) -> str:
    """Native Markdown image reference for one chart in assets/stats."""
    return f"![{alt}](assets/stats/{stem}{CHART_EXT})"


def render_fast_block(entries: list[LocEntry]) -> str:
    """Render the README block between the FAST markers.

    The chart stays visible right under the summary sentence; the table is
    collapsed into a details block, mirroring the heavy reuse matrix.
    """
    details = ("<details>\n<summary>Lines of code table</summary>\n\n"
               f"{render_loc_table(entries)}\n\n</details>")
    return "\n\n".join([
        "_Fast tier: refreshed automatically on every commit "
        "(pre-commit hook, task generate-fast)._",
        "### Lines of code",
        render_loc_summary(entries),
        render_chart(LOC_CHART,
                     "LOC by area chart: non-blank lines of configuration per area"),
        details,
    ])


def render_heavy_block(doc: Measurements) -> str:
    """Render the README block between the HEAVY markers."""
    date = (doc.measuredAt or "unknown date")[:10]
    details = ("<details>\n<summary>Reuse matrix</summary>\n\n"
               f"{render_reuse_matrix(doc)}\n\n</details>")
    return "\n\n".join([
        "_Heavy tier: refreshed manually with `task generate-heavy`, budgeted "
        "under 5 minutes; package counts come from the built closures. "
        f"Last measured {date}._",
        "### Fleet",
        "One row per host, from the built system and home profiles.",
        render_host_overview_table(doc),
        render_chart(CLOSURE_CHART,
                     "Closure footprint chart: store footprint per host in GiB"),
        render_chart(PACKAGE_CHART,
                     "Package counts chart: system and home package counts per "
                     "host, from the built closures"),
        render_consolidation_line(doc),
        "### Closure reuse",
        "Share of each row host's closure that also appears in the column "
        "host's closure.",
        render_chart(REUSE_CHART,
                     "Closure reuse chart: heatmap of shared closure paths "
                     "between hosts, row share contained in column host"),
        details,
    ])


def replace_region(readme_text: str, start_marker: str, end_marker: str,
                   block: str) -> str:
    """Replace one marker-delimited region, guaranteeing marker newlines."""
    start = readme_text.find(start_marker)
    end = readme_text.find(end_marker)
    if start == -1 or end == -1:
        raise ValueError(f"markers not found in README: {start_marker}")
    if end <= start:
        raise ValueError(
            f"markers out of order in README: {end_marker} precedes {start_marker}"
        )
    return (readme_text[: start + len(start_marker)] + "\n"
            + block.strip("\n") + "\n" + readme_text[end:])


def update_readme(block: str, start_marker: str = FAST_START,
                  end_marker: str = FAST_END,
                  readme_path: Path = README_PATH) -> bool:
    """Write one region into the README; True only when bytes changed.

    False means the README is missing, lacks the markers, or already carries
    exactly this block, so an unchanged refresh never churns mtimes.
    """
    if not readme_path.exists():
        return False
    try:
        updated = replace_region(readme_path.read_text(), start_marker,
                                 end_marker, block)
    except (OSError, ValueError):
        return False
    return write_if_changed(readme_path, updated)


def missing_markers(readme_path: Path = README_PATH,
                    start_marker: str = FAST_START,
                    end_marker: str = FAST_END) -> bool:
    """True when the README exists but does not carry the given markers."""
    try:
        text = readme_path.read_text()
    except OSError:
        return False
    return start_marker not in text or end_marker not in text

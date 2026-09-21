"""Chart rendering for assets/stats.

The fast tier publishes the LOC chart, the heavy tier the closure size,
package counts and closure reuse charts. Every artifact renders on a solid
canvas with the light palette and is written only when its bytes changed.

SVG output is deterministic: text is exported as paths (labels never depend
on viewer fonts) and the root width/height is pinned to CSS pixels matching
the previous raster size (see ``_pin_svg_pixel_size``). matplotlib is
imported lazily; run inside the devenv shell.
"""

from __future__ import annotations

import re
import tempfile
from pathlib import Path

from .pipeline import (
    FAST_CHART_STEMS,
    HEAVY_CHART_STEMS,
    STATS_DIR,
    LocEntry,
    Measurements,
    gib,
    loc_leaf_entries,
)
from .palette import LIGHT, cell_ink, mix_hex
from .util import write_if_changed

#: Chart artifact extension; ``render.render_chart`` derives README refs from it.
CHART_EXT = ".svg"
#: Fixed SVG id hash salt: matplotlib otherwise uses a random UUID per save.
SVG_HASH_SALT = "flake-stats"
#: Figure width, resolution and padding, the README chart recipe.
FIGURE_WIDTH, DPI, PAD_INCHES = 6.2, 160, 0.15
#: Chart heights in inches, per chart.
CHART_HEIGHTS = {
    "closure-size": 2.9,
    "package-counts": 3.2,
    "closure-reuse": 4.4,
    "loc-by-area": 2.7,
}


def short_host(host: str) -> str:
    """Heatmap axis label: ``personal-laptop`` -> ``laptop``, ``server-01`` -> ``srv-01``."""
    short = host.removeprefix("personal-")
    return "srv-" + short[7:] if short.startswith("server-") else short


def _import_pyplot():
    """Import matplotlib with deterministic SVG settings (Agg, text as paths)."""
    try:
        import matplotlib

        matplotlib.use("Agg")
        matplotlib.rcParams["svg.fonttype"] = "path"
        matplotlib.rcParams["svg.hashsalt"] = SVG_HASH_SALT
        import matplotlib.pyplot as plt  # type: ignore[import-untyped]
    except ImportError as exc:  # pragma: no cover - environment dependent
        raise RuntimeError("matplotlib is required; run inside the devenv shell") from exc
    return plt


def _setup(plt, height: float):
    fig, ax = plt.subplots(figsize=(FIGURE_WIDTH, height))
    fig.patch.set_facecolor(LIGHT["surface"])
    ax.set_facecolor(LIGHT["surface"])
    return fig, ax


def _annotate(ax, text: str, xy: tuple[float, float], fontsize: float) -> None:
    ax.annotate(text, xy=xy, xytext=(4, 0), textcoords="offset points", ha="left",
                va="center", fontsize=fontsize, color=LIGHT["ink"],
                fontweight="bold", zorder=6)


#: SVG root element and its point-valued width/height attributes.
_SVG_ROOT_RE = re.compile(r"<svg\b[^>]*>")
_SVG_LENGTH_RE = re.compile(r'(width|height)="([0-9.]+)pt"')


def _pin_svg_pixel_size(path: Path) -> None:
    """Rewrite the SVG root size from points to the intended CSS pixels.

    matplotlib writes width/height in points (figure bbox inches times 72);
    the viewBox keeps the point units, so ``pt * DPI / 72`` reproduces the
    intended pixel dimensions while the chart still scales cleanly.
    """
    text = path.read_text(encoding="utf-8")
    root = _SVG_ROOT_RE.search(text)
    if root is None:
        raise ValueError(f"no <svg> root element in {path}")

    def to_css_px(match: re.Match[str]) -> str:
        return f'{match.group(1)}="{round(float(match.group(2)) * DPI / 72)}"'

    sized = _SVG_LENGTH_RE.sub(to_css_px, root.group(0))
    path.write_text(text[: root.start()] + sized + text[root.end() :], encoding="utf-8")


def _finish(plt, fig, ax, path: Path, axis: str) -> None:
    """Axis styling, grid, tight layout, save and close."""
    ax.tick_params(axis="both", which="both", length=0, pad=4, labelsize=9.5,
                   labelcolor=LIGHT["ink_muted"])
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)
    for side in ("left", "bottom"):
        ax.spines[side].set_color(LIGHT["grid_strong"])
        ax.spines[side].set_linewidth(0.8)
    (ax.yaxis if axis == "y" else ax.xaxis).grid(True, color=LIGHT["grid"],
                                                 linewidth=0.8, zorder=0)
    ax.set_axisbelow(True)
    plt.tight_layout()
    fig.savefig(path, dpi=DPI, bbox_inches="tight", pad_inches=PAD_INCHES,
                facecolor=LIGHT["surface"], metadata={"Date": None})
    _pin_svg_pixel_size(path)
    plt.close(fig)


def _render_hbar(plt, out_dir: Path, stem: str, rows, fills: list[str],
                 value_fmt: str, fontsize: float, xlabel: str) -> None:
    """Shared horizontal bar chart: ``rows`` pre-sorted, fills per index."""
    fig, ax = _setup(plt, CHART_HEIGHTS[stem])
    if rows:
        values = [row[1] for row in rows]
        positions = list(range(len(rows)))
        ax.barh(positions, values, height=0.6, color=fills, edgecolor="none", zorder=2)
        ax.set_yticks(positions)
        ax.set_yticklabels([row[0] for row in rows], fontsize=9.5)
        ax.set_xlim(0, max(values) * 1.14 if max(values) > 0 else 1.0)
        for position, value in zip(positions, values):
            _annotate(ax, value_fmt.format(value), (value, position), fontsize)
    ax.set_xlabel(xlabel, fontsize=10, color=LIGHT["ink_muted"])
    _finish(plt, fig, ax, out_dir / f"{stem}{CHART_EXT}", "x")


def _render_closure_size(plt, doc: Measurements, out_dir: Path) -> None:
    rows = [(host, gib(closure.size_bytes)) for host in doc.hosts()
            if (closure := doc.closures.get(host)) is not None and not closure.error]
    rows.sort(key=lambda row: (row[1], row[0]))
    _render_hbar(plt, out_dir, "closure-size", rows, [LIGHT["a2"]] * len(rows),
                 "{:.2f}", 9, "GiB")


def _render_loc_by_area(plt, entries: list[LocEntry], out_dir: Path) -> None:
    rows = [(entry.component, entry.lines) for entry in loc_leaf_entries(entries)]
    rows.sort(key=lambda row: (row[1], row[0]))
    fills = [LIGHT["a1"]] * (len(rows) - 1) + [LIGHT["a2"]] if rows else []
    _render_hbar(plt, out_dir, "loc-by-area", rows, fills, "{:,}", 8.5,
                 "non-blank lines")


def _render_package_counts(plt, doc: Measurements, out_dir: Path) -> None:
    hosts = doc.hosts()

    def counts(attribute: str) -> list[int]:
        return [
            getattr(closure, attribute) if closure and not closure.error else 0
            for closure in (doc.closures.get(host) for host in hosts)
        ]

    rows = sorted(
        (
            (host, system, home if home > 0 else None)
            for host, system, home in zip(
                hosts, counts("systemPackages"), counts("homePackages"), strict=True
            )
        ),
        key=lambda row: (row[1], row[0]),
    )
    fig, ax = _setup(plt, CHART_HEIGHTS["package-counts"])
    if rows:
        labels = [row[0] for row in rows]
        positions = list(range(len(labels)))
        height, offset = 0.38, 0.38 / 2 + 0.02
        system_values = [row[1] for row in rows]
        home_values = [row[2] for row in rows]
        ax.barh([position + offset for position in positions], system_values,
                height=height, color=LIGHT["a3"], edgecolor="none", label="system",
                zorder=2)
        ax.barh([position - offset for position in positions],
                [value or 0 for value in home_values], height=height,
                color=LIGHT["a4"], edgecolor="none", label="home", zorder=2)
        ax.set_yticks(positions)
        ax.set_yticklabels(labels, fontsize=9.5)
        top = max(system_values + [value for value in home_values if value])
        ax.set_xlim(0, top * 1.14 if top > 0 else 1.0)
        for values, shift in ((system_values, offset), (home_values, -offset)):
            for position, value in zip(positions, values):
                if value is not None:
                    _annotate(ax, f"{value:,}", (value, position + shift), 8.5)
        ax.legend(loc="lower right", frameon=False, fontsize=9,
                  labelcolor=LIGHT["ink_muted"], handlelength=1.1,
                  handleheight=0.7, borderaxespad=0.2)
    ax.set_xlabel("packages", fontsize=10, color=LIGHT["ink_muted"])
    _finish(plt, fig, ax, out_dir / f"package-counts{CHART_EXT}", "x")


def _render_closure_reuse(plt, doc: Measurements, out_dir: Path) -> None:
    import numpy as np  # type: ignore[import-untyped]
    from matplotlib.colors import LinearSegmentedColormap  # type: ignore[import-untyped]

    reuse = doc.reuse
    hosts = list(reuse.hosts)
    size = len(hosts)
    fig, ax = plt.subplots(figsize=(5.3, CHART_HEIGHTS["closure-reuse"]))
    fig.patch.set_facecolor(LIGHT["surface"])
    ax.set_facecolor(LIGHT["surface"])
    if size:
        matrix = np.array(
            [[reuse.matrix[r][c] if reuse.matrix.get(r, {}).get(c) is not None
              else np.nan for c in hosts] for r in hosts], dtype=float)
        cmap = LinearSegmentedColormap.from_list(
            "nebula", [LIGHT["grid"], LIGHT["a1"]]).with_extremes(
                bad=(1.0, 1.0, 1.0, 0.0))
        ax.imshow(np.ma.masked_invalid(matrix), cmap=cmap, vmin=0, vmax=100,
                  aspect="equal")
        labels = [short_host(host) for host in hosts]
        ax.set_xticks(range(size))
        ax.set_yticks(range(size))
        # Column hosts read along the top, row hosts on the left.
        ax.xaxis.tick_top()
        ax.xaxis.set_label_position("top")
        ax.set_xticklabels(labels, rotation=24, ha="right", fontsize=9)
        ax.set_yticklabels(labels, fontsize=9)
        ax.tick_params(length=0, pad=3, labelcolor=LIGHT["ink_muted"])
        for side in ax.spines.values():
            side.set_visible(False)
        for row_index, row in enumerate(hosts):
            for column_index, column in enumerate(hosts):
                value = reuse.matrix.get(row, {}).get(column)
                if value is None:
                    continue
                fill = mix_hex(LIGHT["grid"], LIGHT["a1"], value / 100)
                ax.text(column_index, row_index, f"{value:.0f}", ha="center",
                        va="center", fontsize=10, fontweight="bold",
                        color=cell_ink(fill))
        borders = [index - 0.5 for index in range(size + 1)]
        ax.set_xticks(borders, minor=True)
        ax.set_yticks(borders, minor=True)
        ax.grid(which="minor", color=LIGHT["grid"], linewidth=0.8)
        ax.tick_params(which="minor", length=0)
    plt.tight_layout()
    fig.savefig(out_dir / f"closure-reuse{CHART_EXT}", dpi=DPI,
                bbox_inches="tight", pad_inches=PAD_INCHES,
                facecolor=LIGHT["surface"], metadata={"Date": None})
    _pin_svg_pixel_size(out_dir / f"closure-reuse{CHART_EXT}")
    plt.close(fig)


def _publish(out_dir: Path, stems: tuple[str, ...], renderers: dict) -> list[Path]:
    """Render *stems* into a staging dir and publish only changed bytes."""
    plt = _import_pyplot()
    out_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="flake-stats-charts-") as temp:
        staging = Path(temp)
        for stem in stems:
            renderers[stem](plt, staging)
        changed = []
        for path in (staging / f"{stem}{CHART_EXT}" for stem in stems):
            target = out_dir / path.name
            if write_if_changed(target, path.read_bytes()):
                changed.append(target)
        return changed


def render_fast_charts(entries: list[LocEntry], out_dir: Path = STATS_DIR) -> list[Path]:
    """Publish the LOC chart; returns the files whose bytes changed."""
    return _publish(out_dir, FAST_CHART_STEMS,
                    {"loc-by-area": lambda plt, staging: _render_loc_by_area(plt, entries, staging)})


def render_heavy_charts(doc: Measurements, out_dir: Path = STATS_DIR) -> list[Path]:
    """Publish the three heavy charts; returns the files whose bytes changed."""
    return _publish(out_dir, HEAVY_CHART_STEMS, {
        "closure-size": lambda plt, staging: _render_closure_size(plt, doc, staging),
        "package-counts": lambda plt, staging: _render_package_counts(plt, doc, staging),
        "closure-reuse": lambda plt, staging: _render_closure_reuse(plt, doc, staging),
    })

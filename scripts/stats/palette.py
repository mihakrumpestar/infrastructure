"""Palette derived from assets/backgrounds/nebula-8k-wallpaper.jpg.

Single source of truth for every published chart color. ``LIGHT`` is the
GitHub light canvas all artifacts are tuned to; contrast is measured against
``surface``.
"""

from __future__ import annotations

#: GitHub light canvas roles. Contrast is measured against ``surface``.
LIGHT: dict[str, str] = {
    "surface": "#ffffff",
    "alt_surface": "#f6f8fa",
    "ink": "#1f2328",
    "ink_muted": "#57606a",
    "grid": "#d8dee4",
    "grid_strong": "#b6c2cc",
    "a1": "#0e7490",
    "a2": "#115e59",
    "a3": "#1d4ed8",
    "a4": "#6d28d9",
}


def to_rgb(color: str) -> tuple[int, int, int]:
    value = color.lstrip("#")
    if len(value) != 6:
        raise ValueError(f"expected a 6 digit hex color, got {color!r}")
    return tuple(int(value[i : i + 2], 16) for i in (0, 2, 4))  # type: ignore[return-value]


def contrast_ratio(color_a: str, color_b: str) -> float:
    """WCAG contrast ratio between two hex colors."""

    def luminance(color: str) -> float:
        def channel(value: int) -> float:
            v = value / 255.0
            return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4

        red, green, blue = (channel(value) for value in to_rgb(color))
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue

    darker, lighter = sorted((luminance(color_a), luminance(color_b)))
    return (lighter + 0.05) / (darker + 0.05)


def mix_hex(start: str, end: str, fraction: float) -> str:
    fraction = min(max(fraction, 0.0), 1.0)
    first, second = to_rgb(start), to_rgb(end)
    return "#" + "".join(
        f"{round(first[i] + (second[i] - first[i]) * fraction):02x}" for i in range(3)
    )


def cell_ink(fill: str) -> str:
    """The better contrasting ink for text on an interpolated heatmap fill."""
    dark_ink, light_ink = LIGHT["ink"], LIGHT["alt_surface"]
    if contrast_ratio(dark_ink, fill) >= contrast_ratio(light_ink, fill):
        return dark_ink
    return light_ink

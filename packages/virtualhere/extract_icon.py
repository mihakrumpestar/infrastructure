"""Extract the VirtualHere GUI's window icon from the vhuit64 binary.

Ground truth (verified 2026-09-06 via _NET_WM_ICON of a live instance): the
window icon is the LAST PNG of a contiguous cluster of exactly 4 square
128x128 PNGs; the other three are tray state variants. The same bytes exist
as the virtualhere.com favicon (spinning-icon-skyblue128-1_2.png). Wayland
resolves icons via .desktop -> Icon name, never the in-process wxWidgets
icon. The cluster rule is empirical: the script exits 1 on any shape drift
(count/sizes) so it is re-derived instead of silently picking wrong art.

Usage: python3 extract_icon.py <binary> <icon-name> <hicolor-icons-root>
"""

import os
import re
import struct
import sys

PNG_MAGIC = re.compile(rb"\x89PNG\r\n\x1a\n")
CHUNK_TYPE = re.compile(rb"[A-Za-z]{4}")
# End-to-start distance between PNGs of the same cluster.
CLUSTER_GAP = 4096
# Verified cluster shape of the pinned binary.
EXPECTED_COUNT = 4
EXPECTED_SIZE = (128, 128)
MIN_ICON = 64
MAX_ICON = 512


def png_streams(blob):
    """Yield (offset, width, height, png_bytes) for every structurally valid PNG."""
    for match in PNG_MAGIC.finditer(blob):
        pos = match.start() + 8
        width = height = None
        while pos + 8 <= len(blob):
            (length,) = struct.unpack(">I", blob[pos : pos + 4])
            chunk_type = blob[pos + 4 : pos + 8]
            if not CHUNK_TYPE.fullmatch(chunk_type):
                break
            if pos + 12 + length > len(blob):
                break  # truncated chunk: not a valid stream
            if chunk_type == b"IHDR" and length == 13:
                width, height = struct.unpack(">II", blob[pos + 8 : pos + 16])
            pos += 12 + length
            if chunk_type == b"IEND":
                yield (match.start(), width, height, blob[match.start() : pos])
                break


def main():
    if len(sys.argv) != 4:
        sys.exit(f"usage: python3 {sys.argv[0]} <binary> <icon-name> <hicolor-icons-root>")
    binary, icon_name, icons_root = sys.argv[1:4]

    with open(binary, "rb") as handle:
        blob = handle.read()
    icons = [
        (offset, width, height, png)
        for offset, width, height, png in png_streams(blob)
        if width is not None and width == height and MIN_ICON <= width <= MAX_ICON
    ]
    if not icons:
        sys.exit(f"no embedded square icon PNG found in {binary}")

    # Cluster by end-to-start distance; largest cluster, last member.
    clusters = []
    for entry in icons:
        previous = clusters[-1][-1] if clusters else None
        previous_end = previous[0] + len(previous[3]) if previous else None
        if previous is not None and entry[0] - previous_end <= CLUSTER_GAP:
            clusters[-1].append(entry)
        else:
            clusters.append([entry])
    cluster = max(enumerate(clusters), key=lambda pair: (len(pair[1]), pair[0]))[1]

    sizes = {(width, height) for _, width, height, _ in cluster}
    if len(cluster) != EXPECTED_COUNT or sizes != {EXPECTED_SIZE}:
        sys.exit(
            f"icon cluster shape changed: {len(cluster)} PNGs with sizes "
            f"{sorted(sizes)} (expected {EXPECTED_COUNT} of {EXPECTED_SIZE}); "
            "re-derive the window-icon selection rule against a live instance"
        )

    width, height, png = cluster[-1][1], cluster[-1][2], cluster[-1][3]
    target = f"{icons_root}/{width}x{height}/apps/{icon_name}.png"
    os.makedirs(os.path.dirname(target), exist_ok=True)
    with open(target, "wb") as handle:
        handle.write(png)
    print(f"extracted window icon {width}x{height} ({len(png)} bytes) -> {target}")


if __name__ == "__main__":
    main()

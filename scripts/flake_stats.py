#!/usr/bin/env python3
"""NixOS configuration statistics generator.

Fast (default) refreshes LOC and the fast README region; --heavy measures host
closures and reuse (manual, under 5 minutes). Run inside the devenv shell:
    python3 scripts/flake_stats.py [--heavy] [--hosts H ...] [--keep N] [--dry-run]
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from stats.cli import main  # noqa: E402

if __name__ == "__main__":
    raise SystemExit(main())

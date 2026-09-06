"""Make the flake's updater script importable from the tests."""

import sys
from pathlib import Path

LIB_DIR = Path(__file__).resolve().parent.parent
if str(LIB_DIR) not in sys.path:
    sys.path.insert(0, str(LIB_DIR))

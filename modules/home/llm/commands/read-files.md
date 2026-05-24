---
description: Read one or more files with line numbers (e.g. /read-files foo.rs bar.toml)
---

!`for f in $ARGUMENTS; do echo "=== $f ==="; cat -n "$f" 2>&1 || echo "[file not found: $f]"; echo; done`
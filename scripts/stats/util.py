"""Subprocess helpers, byte-stable writes, run-dir retention and stage timing."""

from __future__ import annotations

import json
import shutil
import subprocess
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator

#: Repository root, the working directory of every external command.
REPO_ROOT = Path(__file__).resolve().parents[2]
#: Return code reported when a command exceeds its timeout.
TIMEOUT_RETURNCODE = 124


def run(cmd: list[str], cwd: Path | None = None, timeout: float | None = None):
    """Run a command; failures and timeouts are returned, never raised.

    A timeout is reported as returncode 124 with a descriptive stderr.
    """
    try:
        return subprocess.run(cmd, capture_output=True, text=True,
                              cwd=cwd or REPO_ROOT, timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        stderr = (exc.stderr or b"").decode(errors="replace") if exc.stderr else ""
        return subprocess.CompletedProcess(cmd, TIMEOUT_RETURNCODE, stdout="",
                                           stderr=f"timed out after {timeout}s\n{stderr}".strip())


def nix_eval_json(attr: str, apply: str | None = None, timeout: float | None = None):
    """Evaluate ``path:.#<attr>`` to JSON, returning None on any failure."""
    cmd = ["nix", "eval", "--json", f"path:.#{attr}"]
    if apply:
        cmd += ["--apply", apply]
    result = run(cmd, timeout=timeout)
    if result.returncode != 0:
        return None
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return None


def nix_eval_raw(attr: str, timeout: float | None = None) -> str:
    """Evaluate ``path:.#<attr>`` to a raw string, empty on failure."""
    result = run(["nix", "eval", "--raw", f"path:.#{attr}"], timeout=timeout)
    return result.stdout.strip() if result.returncode == 0 else ""


def write_if_changed(path: Path, content: str | bytes) -> bool:
    """Write only differing bytes (parents created); True when written.

    An unchanged refresh never touches the file, so mtimes stay stable.
    """
    data = content.encode() if isinstance(content, str) else content
    try:
        if path.read_bytes() == data:
            return False
    except OSError:
        pass
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return True


def prune_runs(root: Path, prefixes: tuple[str, ...], keep: int) -> list[Path]:
    """Delete all but the newest ``keep`` run dirs per prefix; return deletions."""
    keep = max(keep, 0)
    deleted: list[Path] = []
    for prefix in prefixes:
        if not root.exists():
            break
        runs = sorted(
            (p for p in root.iterdir()
             if p.is_dir() and not p.is_symlink() and p.name.startswith(prefix)),
            key=lambda p: p.name,
        )
        for old_run in runs[:-keep] if keep else runs:
            shutil.rmtree(old_run)
            deleted.append(old_run)
    return deleted


class Stage:
    """Canonical stage names, shared by producers and the timing table."""

    HOST_MATRIX = "host matrix eval"
    CLOSURE_BUILDS = "closure builds"
    CLOSURE_SIZES = "closure sizes"
    CLOSURE_REFS = "closure refs"
    CLOSURE_REUSE = "closure reuse"
    LOC = "LOC"
    RENDER = "render"
    CHARTS = "charts"
    RETENTION = "retention"


class Timing:
    """Per-stage wall clock, first-seen order, repeats summed in place."""

    def __init__(self) -> None:
        self._rows: list[list] = []

    @contextmanager
    def stage(self, name: str) -> Iterator[None]:
        started = time.monotonic()
        try:
            yield
        finally:
            self.record(name, time.monotonic() - started)

    def record(self, name: str, seconds: float) -> None:
        for row in self._rows:
            if row[0] == name:
                row[1] += seconds
                return
        self._rows.append([name, seconds])

    def table(self) -> str:
        """Plain text table with a TOTAL row."""
        width = max([len(name) for name, _ in self._rows] + [len("Stage")])
        rows = [f"{name:<{width}}  {seconds:>9.3f}" for name, seconds in self._rows]
        total = sum(seconds for _, seconds in self._rows)
        rule = f"{'-' * width}  {'-' * 9}"
        return "\n".join([f"{'Stage':<{width}}  {'Seconds':>9}", rule, *rows, rule,
                          f"{'TOTAL':<{width}}  {total:>9.3f}"])

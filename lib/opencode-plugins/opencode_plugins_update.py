#!/usr/bin/env python3
"""Update the opencode plugin pins in a Nix file against npm dist-tags.

Reads the `opencodePluginPins` attrset (name -> { version, hash }), compares
each version against the npm dist-tag, and by default rewrites the pins in
place. A null hash marks the npm spec lane; a sha256 hash marks the hermetic
store-path lane (tarball hash prefetched via `nix store prefetch-file`,
so `nix` must be on PATH).

Usage:
    task update-opencode-plugins                        # in the infrastructure repo
    opencode-plugins-update --file <pins-file>          # direct
    opencode-plugins-update --file <pins-file> --dry-run  # report only
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import urllib.request
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any

NPM_REGISTRY = "https://registry.npmjs.org"

Metadata = Mapping[str, Any]
FetchMetadata = Callable[[str], Metadata]
PrefetchHash = Callable[[str], str]

# One pin stanza inside the opencodePluginPins attrset. Attribute names may
# be quoted (scoped packages); hash is a quoted sha256 or null (npm spec
# lane). Matches the nixfmt-canonical multi-line layout.
PIN_RE = re.compile(
    r'(?P<pad>[ \t]*)(?P<quote>"?)(?P<name>[@\w./-]+)(?P=quote) = \{\n'
    r'(?P<vpad>[ \t]*)version = "(?P<version>[^"]+)";\n'
    r'[ \t]*hash = (?P<hash>null|"[^"]+");\n'
    r"(?P<epad>[ \t]*)\};"
)

# Attrset-stanza opener inside the block (any shape): the drift guard
# requires every declared stanza to parse strictly.
STANZA_RE = re.compile(r'^[ \t]*(?:"([^"]+)"|([@/\w.-]+)) = \{', re.MULTILINE)

PINS_HEADER_RE = re.compile(r"opencodePluginPins = \{")


class PinParseError(RuntimeError):
    """The pins block could not be parsed."""


class TarballError(RuntimeError):
    """The registry metadata has no tarball for a version."""


@dataclass(frozen=True, slots=True)
class Pin:
    name: str
    version: str
    tarball_hash: str | None

    @property
    def hermetic(self) -> bool:
        return self.tarball_hash is not None


@dataclass(frozen=True, slots=True)
class Update:
    version: str
    tarball_hash: str | None


def pins_span(text: str) -> tuple[int, int]:
    """Character span of the opencodePluginPins attrset body.

    Raises PinParseError when the attrset is missing or not closed.
    """
    header = PINS_HEADER_RE.search(text)
    if header is None:
        raise PinParseError("opencodePluginPins attrset not found")
    start = header.end()
    depth = 1
    in_string = False
    escaped = False
    for i in range(start, len(text)):
        char = text[i]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return start, i
    raise PinParseError("opencodePluginPins attrset is not closed")


def parse_pins(text: str) -> list[Pin]:
    start, end = pins_span(text)
    block = text[start:end]
    pins = [
        Pin(
            name=match["name"],
            version=match["version"],
            tarball_hash=None if match["hash"] == "null" else match["hash"].strip('"'),
        )
        for match in PIN_RE.finditer(block)
    ]
    # Drift guard: every stanza declared in the block must parse strictly,
    # otherwise a reformatted pin would be skipped silently.
    declared = {m.group(1) or m.group(2) for m in STANZA_RE.finditer(block)}
    unparsed = sorted(declared - {pin.name for pin in pins})
    if unparsed:
        raise PinParseError(
            "pin stanzas drifted from the expected shape: " + ", ".join(unparsed)
        )
    if not pins:
        raise PinParseError(
            f"no plugin pins found (expected shape: {PIN_RE.pattern!r})"
        )
    return pins


def render_pins(text: str, updates: Mapping[str, Update]) -> str:
    """Return text with each updated pin's stanza rewritten in place."""
    start, end = pins_span(text)
    block = text[start:end]

    def replace(match: re.Match[str]) -> str:
        update = updates.get(match["name"])
        if update is None:
            return match[0]
        hash_repr = (
            "null" if update.tarball_hash is None else f'"{update.tarball_hash}"'
        )
        quote = match["quote"]
        vpad, epad, pad = match["vpad"], match["epad"], match["pad"]
        return (
            f"{pad}{quote}{match['name']}{quote} = {{\n"
            f'{vpad}version = "{update.version}";\n'
            f"{vpad}hash = {hash_repr};\n"
            f"{epad}}};"
        )

    return text[:start] + PIN_RE.sub(replace, block) + text[end:]


def tarball_url(metadata: Metadata, version: str) -> str:
    try:
        return str(metadata["versions"][version]["dist"]["tarball"])  # type: ignore[index]
    except (KeyError, TypeError) as error:
        raise TarballError(f"no tarball for version {version}") from error


def collect_updates(
    pins: Sequence[Pin],
    fetch_metadata: FetchMetadata,
    prefetch_hash: PrefetchHash | None,
) -> tuple[dict[str, Update], list[str]]:
    """Return (updates, errors): newer versions per plugin, failure messages.

    Tarball hashes are only resolved (prefetched) when prefetch_hash is
    given; report-only runs pass None and hermetic updates then carry a
    null hash. Errors list plugins that could not be checked or updated.
    """
    updates: dict[str, Update] = {}
    errors: list[str] = []
    for pin in pins:
        try:
            metadata = fetch_metadata(pin.name)
            latest = str(metadata["dist-tags"]["latest"])
        except (KeyError, TypeError, ValueError, OSError) as error:
            errors.append(f"registry lookup failed for {pin.name}: {error}")
            continue
        if latest == pin.version:
            continue
        new_hash = None
        if pin.tarball_hash is not None and prefetch_hash is not None:
            try:
                new_hash = prefetch_hash(tarball_url(metadata, latest))
            except (
                KeyError,
                TarballError,
                ValueError,
                OSError,
                subprocess.SubprocessError,
            ) as error:
                errors.append(f"could not update {pin.name} to {latest}: {error}")
                continue
        updates[pin.name] = Update(version=latest, tarball_hash=new_hash)
    return updates, errors


def default_fetch_metadata(name: str) -> Metadata:
    with urllib.request.urlopen(f"{NPM_REGISTRY}/{name}", timeout=30) as response:
        return json.load(response)


def default_prefetch_hash(url: str) -> str:
    completed = subprocess.run(
        ["nix", "store", "prefetch-file", "--json", url],
        check=True,
        capture_output=True,
        text=True,
        timeout=120,
    )
    return str(json.loads(completed.stdout)["hash"])


def main(
    argv: Sequence[str] | None = None,
    *,
    fetch_metadata: FetchMetadata = default_fetch_metadata,
    prefetch_hash: PrefetchHash = default_prefetch_hash,
) -> int:
    parser = argparse.ArgumentParser(
        prog="opencode-plugins-update",
        description=__doc__.splitlines()[0],
    )
    parser.add_argument(
        "--file",
        type=Path,
        required=True,
        help="Nix file containing the opencodePluginPins attrset",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="report updates without rewriting the file",
    )
    args = parser.parse_args(argv)

    try:
        text = args.file.read_text(encoding="utf-8")
        pins = parse_pins(text)
    except (OSError, PinParseError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    updates, errors = collect_updates(
        pins,
        fetch_metadata,
        None if args.dry_run else prefetch_hash,
    )

    for pin in pins:
        lane = "hermetic" if pin.hermetic else "npm"
        update = updates.get(pin.name)
        status = f"-> {update.version}" if update else "up to date"
        print(f"{pin.name:40s} {lane:8s} {pin.version:10s} {status}")
    for error in errors:
        print(f"error: {error}", file=sys.stderr)

    if updates and not args.dry_run:
        args.file.write_text(render_pins(text, updates), encoding="utf-8")
        for name, update in updates.items():
            print(f"updated {name} -> {update.version}")
    elif updates:
        print("dry run: run without --dry-run to apply")
    else:
        print("nothing to update")

    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())

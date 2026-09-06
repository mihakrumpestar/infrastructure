"""Unit tests for scripts/opencode_plugins_update.py."""

from __future__ import annotations

import subprocess
from pathlib import Path

import opencode_plugins_update as ocu

SAMPLE = """  opencodePluginPins = {
    cc-safety-net = {
      version = "2.3.3";
      hash = "sha256-v4WRzS5OJXN/WmKNpw3tKEtTnj2tEKoXckGQakcv/MI=";
    };

    "@cortexkit/opencode-magic-context" = {
      version = "0.41.3";
      hash = null;
    };

    oh-my-opencode-slim = {
      version = "2.2.18";
      hash = null;
    };

    opencode-auto-resume = {
      version = "1.1.13";
      hash = "sha256-5P4SwsgxZsdDfRl6v3s3mfe+Li37eu+EVRDn8LqK3OQ=";
    };
  };
"""

CC_HASH = "sha256-v4WRzS5OJXN/WmKNpw3tKEtTnj2tEKoXckGQakcv/MI="
AR_HASH = "sha256-5P4SwsgxZsdDfRl6v3s3mfe+Li37eu+EVRDn8LqK3OQ="

PINNED = {
    "cc-safety-net": "2.3.3",
    "@cortexkit/opencode-magic-context": "0.41.3",
    "oh-my-opencode-slim": "2.2.18",
    "opencode-auto-resume": "1.1.13",
}


def make_metadata(latest: str) -> dict[str, object]:
    return {
        "dist-tags": {"latest": latest},
        "versions": {
            latest: {
                "dist": {
                    "tarball": f"https://registry.npmjs.org/pkg/-/pkg-{latest}.tgz"
                }
            }
        },
    }


def make_fetch(latest_by_name: dict[str, str]) -> ocu.FetchMetadata:
    def fetch(name: str) -> dict[str, object]:
        return make_metadata(latest_by_name[name])

    return fetch


def pinned_fetch(**newer: str) -> ocu.FetchMetadata:
    """Fake registry where every plugin is at its pinned version except overrides."""
    return make_fetch(PINNED | newer)


# --- parsing -----------------------------------------------------------------


def test_parse_pins_reads_all_lanes() -> None:
    pins = ocu.parse_pins(SAMPLE)
    assert [(p.name, p.version, p.tarball_hash) for p in pins] == [
        ("cc-safety-net", "2.3.3", CC_HASH),
        ("@cortexkit/opencode-magic-context", "0.41.3", None),
        ("oh-my-opencode-slim", "2.2.18", None),
        ("opencode-auto-resume", "1.1.13", AR_HASH),
    ]


def test_parse_pins_lane_property() -> None:
    pins = {p.name: p for p in ocu.parse_pins(SAMPLE)}
    assert pins["cc-safety-net"].hermetic is True
    assert pins["oh-my-opencode-slim"].hermetic is False


def test_parse_pins_rejects_empty_text() -> None:
    try:
        ocu.parse_pins("no pins here")
    except ocu.PinParseError:
        return
    raise AssertionError("expected PinParseError")


# --- scoping and drift guard ---------------------------------------------------


def test_parse_pins_ignores_same_shape_outside_block() -> None:
    text = (
        SAMPLE
        + """
  someOtherPins = {
    decoy = {
      version = "9.9.9";
      hash = null;
    };
  };
"""
    )
    pins = ocu.parse_pins(text)
    assert [p.name for p in pins] == [
        "cc-safety-net",
        "@cortexkit/opencode-magic-context",
        "oh-my-opencode-slim",
        "opencode-auto-resume",
    ]


def test_parse_pins_rejects_drifted_stanza_loudly() -> None:
    text = SAMPLE.replace(
        """      version = "1.1.13";
      hash = "sha256-5P4SwsgxZsdDfRl6v3s3mfe+Li37eu+EVRDn8LqK3OQ=";
    };""",
        """      hash = null;
      version = "1.1.13";
    };""",
    )
    try:
        ocu.parse_pins(text)
    except ocu.PinParseError as error:
        assert "opencode-auto-resume" in str(error)
        return
    raise AssertionError("expected PinParseError for drifted stanza")


def test_parse_pins_rejects_missing_block() -> None:
    try:
        ocu.parse_pins("opencodePluginPins deleted")
    except ocu.PinParseError:
        return
    raise AssertionError("expected PinParseError for missing block")


def test_parse_pins_rejects_unclosed_block() -> None:
    # drop from the final closing brace so the attrset never closes
    truncated = SAMPLE[: SAMPLE.rfind("}")]
    try:
        ocu.parse_pins(truncated)
    except ocu.PinParseError:
        return
    raise AssertionError("expected PinParseError for unclosed block")


# --- rendering ----------------------------------------------------------------


def test_render_pins_no_updates_is_identity() -> None:
    assert ocu.render_pins(SAMPLE, {}) == SAMPLE


def test_render_pins_rewrites_version_and_hash() -> None:
    updates = {"cc-safety-net": ocu.Update("2.3.4", "sha256-newhash")}
    rendered = ocu.render_pins(SAMPLE, updates)
    pins = {p.name: p for p in ocu.parse_pins(rendered)}
    assert pins["cc-safety-net"].version == "2.3.4"
    assert pins["cc-safety-net"].tarball_hash == "sha256-newhash"
    # untouched pins stay byte-identical
    assert pins["oh-my-opencode-slim"].version == "2.2.18"


def test_render_pins_keeps_null_hash_for_npm_lane() -> None:
    updates = {"oh-my-opencode-slim": ocu.Update("2.3.0", None)}
    pins = {p.name: p for p in ocu.parse_pins(ocu.render_pins(SAMPLE, updates))}
    assert pins["oh-my-opencode-slim"].version == "2.3.0"
    assert pins["oh-my-opencode-slim"].tarball_hash is None


def test_render_pins_preserves_quoted_scoped_name() -> None:
    updates = {"@cortexkit/opencode-magic-context": ocu.Update("0.42.0", None)}
    rendered = ocu.render_pins(SAMPLE, updates)
    assert '"@cortexkit/opencode-magic-context" = {' in rendered
    pins = {p.name: p for p in ocu.parse_pins(rendered)}
    assert pins["@cortexkit/opencode-magic-context"].version == "0.42.0"


def test_render_pins_round_trip_is_idempotent() -> None:
    updates = {
        "cc-safety-net": ocu.Update("2.3.4", "sha256-newhash"),
        "oh-my-opencode-slim": ocu.Update("2.3.0", None),
    }
    once = ocu.render_pins(SAMPLE, updates)
    assert ocu.render_pins(once, updates) == once


# --- tarball urls -------------------------------------------------------------


def test_tarball_url_from_metadata() -> None:
    url = ocu.tarball_url(make_metadata("1.2.3"), "1.2.3")
    assert url == "https://registry.npmjs.org/pkg/-/pkg-1.2.3.tgz"


def test_tarball_url_missing_version_raises() -> None:
    try:
        ocu.tarball_url(make_metadata("1.2.3"), "9.9.9")
    except ocu.TarballError:
        return
    raise AssertionError("expected TarballError")


# --- update collection --------------------------------------------------------


def test_collect_updates_all_current() -> None:
    pins = ocu.parse_pins(SAMPLE)
    prefetch_calls: list[str] = []
    updates, errors = ocu.collect_updates(pins, pinned_fetch(), prefetch_calls.append)
    assert updates == {}
    assert errors == []
    assert prefetch_calls == []


def test_collect_updates_prefetches_only_hermetic() -> None:
    pins = ocu.parse_pins(SAMPLE)
    fetch = pinned_fetch(**{"cc-safety-net": "2.4.0", "oh-my-opencode-slim": "2.3.0"})
    prefetch_calls: list[str] = []

    def spy(url: str) -> str:
        prefetch_calls.append(url)
        return "sha256-spy"

    updates, errors = ocu.collect_updates(pins, fetch, spy)
    assert errors == []
    assert set(updates) == {"cc-safety-net", "oh-my-opencode-slim"}
    assert updates["cc-safety-net"].tarball_hash == "sha256-spy"
    assert updates["oh-my-opencode-slim"].tarball_hash is None
    assert len(prefetch_calls) == 1


def test_collect_updates_skips_prefetch_when_not_applying() -> None:
    pins = ocu.parse_pins(SAMPLE)
    fetch = pinned_fetch(**{"cc-safety-net": "2.4.0"})
    prefetch_calls: list[str] = []
    updates, errors = ocu.collect_updates(pins, fetch, None)
    assert errors == []
    assert updates["cc-safety-net"].tarball_hash is None
    assert prefetch_calls == []


def test_collect_updates_registry_error() -> None:
    pins = ocu.parse_pins(SAMPLE)

    def failing_fetch(name: str) -> dict[str, object]:
        raise OSError("network down")

    updates, errors = ocu.collect_updates(pins, failing_fetch, lambda url: "")
    assert updates == {}
    assert len(errors) == len(pins)
    assert "network down" in errors[0]


def test_collect_updates_prefetch_error() -> None:
    pins = ocu.parse_pins(SAMPLE)
    fetch = pinned_fetch(**{"cc-safety-net": "2.4.0"})

    def failing_prefetch(url: str) -> str:
        raise subprocess.CalledProcessError(1, "nix")

    updates, errors = ocu.collect_updates(pins, fetch, failing_prefetch)
    assert updates == {}
    assert len(errors) == 1
    assert "cc-safety-net" in errors[0]


# --- main ---------------------------------------------------------------------


def test_main_dry_run_leaves_file(tmp_path: Path, capsys) -> None:
    pins_file = tmp_path / "agent.nix"
    pins_file.write_text(SAMPLE, encoding="utf-8")
    fetch = pinned_fetch(**{"cc-safety-net": "2.4.0"})
    rc = ocu.main(["--file", str(pins_file), "--dry-run"], fetch_metadata=fetch)
    assert rc == 0
    assert pins_file.read_text(encoding="utf-8") == SAMPLE
    assert "-> 2.4.0" in capsys.readouterr().out


def test_main_applies_by_default(tmp_path: Path) -> None:
    pins_file = tmp_path / "agent.nix"
    pins_file.write_text(SAMPLE, encoding="utf-8")
    fetch = pinned_fetch(**{"cc-safety-net": "2.4.0", "opencode-auto-resume": "1.2.0"})
    rc = ocu.main(
        ["--file", str(pins_file)],
        fetch_metadata=fetch,
        prefetch_hash=lambda url: "sha256-prefetched",
    )
    assert rc == 0
    pins = {p.name: p for p in ocu.parse_pins(pins_file.read_text(encoding="utf-8"))}
    assert pins["cc-safety-net"].version == "2.4.0"
    assert pins["cc-safety-net"].tarball_hash == "sha256-prefetched"
    assert pins["opencode-auto-resume"].version == "1.2.0"
    assert pins["opencode-auto-resume"].tarball_hash == "sha256-prefetched"
    assert pins["oh-my-opencode-slim"].version == "2.2.18"


def test_main_no_updates_keeps_file(tmp_path: Path, capsys) -> None:
    pins_file = tmp_path / "agent.nix"
    pins_file.write_text(SAMPLE, encoding="utf-8")
    rc = ocu.main(["--file", str(pins_file)], fetch_metadata=pinned_fetch())
    assert rc == 0
    assert pins_file.read_text(encoding="utf-8") == SAMPLE
    assert "nothing to update" in capsys.readouterr().out


def test_main_error_returns_nonzero(tmp_path: Path) -> None:
    pins_file = tmp_path / "agent.nix"
    pins_file.write_text(SAMPLE, encoding="utf-8")

    def failing_fetch(name: str) -> dict[str, object]:
        raise OSError("network down")

    rc = ocu.main(["--file", str(pins_file)], fetch_metadata=failing_fetch)
    assert rc == 1
    assert pins_file.read_text(encoding="utf-8") == SAMPLE


def test_main_unparsable_file_returns_nonzero(tmp_path: Path) -> None:
    pins_file = tmp_path / "agent.nix"
    pins_file.write_text("no pins", encoding="utf-8")
    rc = ocu.main(["--file", str(pins_file)], fetch_metadata=make_fetch({}))
    assert rc == 1


def test_main_requires_file() -> None:
    try:
        ocu.main([], fetch_metadata=make_fetch({}))
    except SystemExit as exit_:
        assert exit_.code == 2  # argparse usage error
        return
    raise AssertionError("expected SystemExit for missing --file")

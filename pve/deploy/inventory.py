"""Static pyinfra inventory.

The aliases resolve through the SSH config. pyinfra uses Paramiko, so the SSH
config's IdentityFile is used to select the matching key from the running SSH
agent.
"""

import base64
import hashlib
import os
import subprocess
from pathlib import Path

import paramiko


def _identity_files(alias: str) -> list[Path]:
    output = subprocess.check_output(
        ["ssh", "-G", alias],
        text=True,
        stderr=subprocess.DEVNULL,
    )
    paths = []
    for line in output.splitlines():
        key, _, value = line.partition(" ")
        if key == "identityfile" and value:
            path = value.strip()
            if path.lower() != "none":
                paths.append(Path(os.path.expanduser(path)))
    return paths


def _blob_fingerprint(blob: bytes) -> str:
    digest = hashlib.sha256(blob).digest()
    return base64.b64encode(digest).decode().rstrip("=")


def _public_key_fingerprint(path: Path) -> str:
    fields = path.read_text().split()
    if len(fields) < 2:
        raise RuntimeError(f"not a public key: {path}")
    return _blob_fingerprint(base64.b64decode(fields[1]))


def _agent_key(alias: str, identity_files: list[Path]) -> paramiko.AgentKey:
    fingerprints = {
        _public_key_fingerprint(path)
        for path in identity_files
        if path.suffix == ".pub"
    }
    if not fingerprints:
        raise RuntimeError(f"{alias}: no .pub IdentityFile to match against the SSH agent")

    for key in paramiko.Agent().get_keys():
        if _blob_fingerprint(key.asbytes()) in fingerprints:
            return key

    raise RuntimeError(
        f"{alias}: no SSH agent key matches the IdentityFile; unlock the agent and load the key"
    )


def _host_data(alias: str) -> dict[str, object]:
    identity_files = _identity_files(alias)
    private_keys = [path for path in identity_files if path.suffix != ".pub"]
    if private_keys:
        return {"ssh_key": str(private_keys[0])}

    return {
        "ssh_paramiko_connect_kwargs": {
            "pkey": _agent_key(alias, identity_files),
            "allow_agent": True,
            "look_for_keys": False,
        }
    }


# ---------------------------------------------------------------------------
# Hosts
# ---------------------------------------------------------------------------

# Add pve-02n when pve-02 is installed.
pve = [(alias, _host_data(alias)) for alias in ("pve-01n", "pve-03n")]

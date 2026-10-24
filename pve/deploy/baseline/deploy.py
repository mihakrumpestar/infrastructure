"""Baseline PVE host configuration.

Called by the single entrypoint `deploy/deploy.py`.
"""

from io import StringIO
from pathlib import Path

from pyinfra.api.deploy import deploy
from pyinfra.context import host
from pyinfra.facts.files import File, FileContents
from pyinfra.facts.server import Command, OsRelease
from pyinfra.operations import apt, files, server


@deploy("baseline")
def baseline():
    # ---------------------------------------------------------------------------
    # Debian release
    # ---------------------------------------------------------------------------

    os_release = host.get_fact(OsRelease) or {}
    suite = os_release.get("version_codename")
    if not suite:
        raise Exception("cannot determine the Debian codename from /etc/os-release")

    # ---------------------------------------------------------------------------
    # APT repositories
    # ---------------------------------------------------------------------------

    enterprise = "/etc/apt/sources.list.d/pve-enterprise.sources"
    if host.get_fact(File, path=enterprise) is not None:
        files.put(
            name="Disable the enterprise repository",
            src=StringIO(
                "Types: deb\n"
                "URIs: https://enterprise.proxmox.com/debian/pve\n"
                f"Suites: {suite}\n"
                "Components: pve-enterprise\n"
                "Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg\n"
                "Enabled: no\n"
            ),
            dest=enterprise,
            mode="644",
        )

    files.put(
        name="Enable the no-subscription repository",
        src=StringIO(
            "Types: deb\n"
            "URIs: http://download.proxmox.com/debian/pve\n"
            f"Suites: {suite}\n"
            "Components: pve-no-subscription\n"
            "Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg\n"
        ),
        dest="/etc/apt/sources.list.d/proxmox.sources",
        mode="644",
    )

    for legacy in (
        "pve-enterprise.list",
        "pve-install-repo.list",
        "pve-no-subscription.list",
        "ceph.list",
    ):
        files.file(
            name=f"Remove legacy source {legacy}",
            path=f"/etc/apt/sources.list.d/{legacy}",
            present=False,
        )

    # Keep the configured Ceph release, but use its no-subscription repository.
    ceph_sources = "/etc/apt/sources.list.d/ceph.sources"
    ceph_lines = host.get_fact(FileContents, path=ceph_sources) or []
    ceph_uri = next(
        (
            line.split(":", 1)[1].strip()
            for line in ceph_lines
            if line.startswith("URIs:")
        ),
        None,
    )
    if ceph_uri:
        ceph_release = ceph_uri.rstrip("/").rsplit("/", 1)[-1]
        files.put(
            name="Switch the Ceph repository to no-subscription",
            src=StringIO(
                "Types: deb\n"
                f"URIs: http://download.proxmox.com/debian/{ceph_release}\n"
                f"Suites: {suite}\n"
                "Components: no-subscription\n"
                "Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg\n"
            ),
            dest=ceph_sources,
            mode="644",
        )

    # ---------------------------------------------------------------------------
    # System upgrade
    # ---------------------------------------------------------------------------

    apt.update(name="Refresh the apt index")
    apt.dist_upgrade(name="Upgrade the node")

    # ---------------------------------------------------------------------------
    # SSH daemon
    # ---------------------------------------------------------------------------

    sshd_config = "/etc/ssh/sshd_config"
    host.get_fact(Command, command="/usr/sbin/sshd -t")

    sshd_source = "deploy/baseline/sshd_config"
    desired = Path(sshd_source).read_text()
    current = host.get_fact(FileContents, path=sshd_config) or []
    if "\n".join(current).rstrip("\n") != desired.rstrip("\n"):
        files.put(
            name="Write the SSH daemon config",
            src=sshd_source,
            dest=sshd_config,
            mode="644",
        )
        server.shell(
            name="Validate and reload sshd",
            commands="/usr/sbin/sshd -t && systemctl reload ssh",
        )

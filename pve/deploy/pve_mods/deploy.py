"""PVE-mods configuration.

Called by the single entrypoint `deploy/deploy.py`.
"""

from pyinfra.api.deploy import deploy
from pyinfra.operations import apt, files, server


@deploy("pve_mods")
def pve_mods():
    # ---------------------------------------------------------------------------
    # Package source
    # ---------------------------------------------------------------------------

    PVE_MODS_VERSION = "2.1.1"
    PVE_MODS_SHA256 = "ec3a892602e502983513035bf992b2ad71077c56cc0f3bc464629841519f85b4"
    PVE_MODS_DEB = (
        "https://github.com/Meliox/PVE-mods/releases/download/"
        f"v{PVE_MODS_VERSION}/pve-mods_{PVE_MODS_VERSION}_all.deb"
    )
    PVE_MODS_CACHE_DIR = "/var/cache/pve-mods"
    PVE_MODS_CACHE = f"{PVE_MODS_CACHE_DIR}/pve-mods_{PVE_MODS_VERSION}_all.deb"

    # ---------------------------------------------------------------------------
    # Dependencies
    # ---------------------------------------------------------------------------

    apt.packages(
        name="Install lm-sensors for the node_info module",
        packages=["lm-sensors"],
        update=True,
        cache_time=3600,
    )

    # ---------------------------------------------------------------------------
    # Package cache
    # ---------------------------------------------------------------------------

    files.directory(
        name="Create the PVE-mods package cache",
        path=PVE_MODS_CACHE_DIR,
        mode="755",
    )
    files.download(
        name=f"Cache pve-mods {PVE_MODS_VERSION}",
        src=PVE_MODS_DEB,
        dest=PVE_MODS_CACHE,
        sha256sum=PVE_MODS_SHA256,
        mode="644",
    )

    # ---------------------------------------------------------------------------
    # Package install
    # ---------------------------------------------------------------------------

    apt.deb(
        name=f"Install pve-mods {PVE_MODS_VERSION}",
        src=PVE_MODS_CACHE,
    )

    # ---------------------------------------------------------------------------
    # Module configuration
    # ---------------------------------------------------------------------------

    files.put(
        name="Enable both PVE-mods modules",
        src="deploy/pve_mods/pve-mods.conf",
        dest="/etc/pve-mods/pve-mods.conf",
        mode="644",
    )

    files.put(
        name="Configure the node_info module",
        src="deploy/pve_mods/node_info.conf",
        dest="/etc/pve-mods/conf.d/node_info.conf",
        mode="644",
    )

    # ---------------------------------------------------------------------------
    # Patch application
    # ---------------------------------------------------------------------------

    server.shell(
        name="Apply the PVE-mods patches",
        commands="/usr/lib/pve-mods/apply-patches.sh",
    )

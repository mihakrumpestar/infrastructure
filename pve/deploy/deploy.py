"""Single pyinfra entrypoint for all PVE features.

Run from pve/:

    pyinfra deploy/inventory.py deploy/deploy.py --limit pve
"""

from deploy.baseline.deploy import baseline
from deploy.pve_mods.deploy import pve_mods

# The baseline runs first so PVE-mods installs onto a configured host.
baseline()
pve_mods()

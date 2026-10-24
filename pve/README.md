# Proxmox VE

Three cluster members and all receive the same baseline. All three run a Ceph MON; pve-01 and pve-02 also host the OSDs and VMs, while pve-03 is MON-only and runs no guests by policy.

## 1. Install

The installer is [pve-autoinstall](https://github.com/mihakrumpestar/pve-autoinstall). It renders one answer file per host, embeds it in a prepared PVE ISO, and validates both.

From the repository root:

```sh
nix run github:mihakrumpestar/pve-autoinstall -- ../infrastructure-secrets/secrets/pve.nix
```

Boot each host from its ISO. The answer is embedded, so no network service is needed during installation.

After the first boot, log in as root over SSH and change the root password.

## 2. Post-install

### 2.1 NetBird

Create a reusable setup key in the NetBird dashboard first. PVE hosts are server peers, so enroll them with the setup key.

```sh
apt-get update
apt-get install ca-certificates curl gnupg -y
curl -sSL https://pkgs.netbird.io/debian/public.key | gpg --dearmor --output /usr/share/keyrings/netbird-archive-keyring.gpg
echo 'deb [signed-by=/usr/share/keyrings/netbird-archive-keyring.gpg] https://pkgs.netbird.io/debian stable main' | tee /etc/apt/sources.list.d/netbird.list
Install NetBird

apt-get update
apt-get install netbird

systemctl enable --now netbird

netbird up --setup-key <setup-key>

netbird status
```

### 2.2 Baseline

The installed nodes get the same baseline, followed by the PVE-mods deploy.

```sh
task pve -- --dry
task pve
```

The first command previews both deploys; the second applies them and asks for confirmation before executing. Add `-y` after `--` for a non-interactive run.

If the upgrade installs a newer PVE kernel, reboot before creating the cluster.

### 2.3 Create and join the cluster

Cluster creation and joining are one-shot operations. Use the GUI or `pvecm`, whichever is easier; do it after the baseline and after any required reboot.

On main node, use **Datacenter > Cluster > Create Cluster**.

The cluster name is fixed at creation time; use up to 15 letters, digits or hyphens.

On other nodes, use **Datacenter > Cluster > Join Cluster**.

`qm list` and `pct list` must show no guests.

### 2.5 Verify

```sh
pvecm status
pvecm nodes
```

`pvecm status` must show all three nodes online, `Expected votes: 3`, `Total votes: 3`, and `Quorate`.

## 3. Ceph

The baseline does not install or configure Ceph. All three PVE nodes run a Ceph MON. pve-01 and pve-02 also host the OSDs; pve-03 is MON-only.

Configure Ceph after the PVE cluster is quorate. Three MONs provide quorum 2, so one MON can fail. The pool data is still only on the two OSD hosts, so size 2 gives one replica per host and min_size 1 keeps I/O available after one OSD host fails, with the data-loss risk described below. A third OSD host would be needed for a third replica.

This assumes Ceph is installed on all three nodes, a MON is running on each, and the OSDs are up on pve-01 and pve-02 (`ceph -s`). Create the VM pool on a Ceph node, for example `pve-01`:

```sh
pveceph pool create <pool> --size 2 --min_size 1 --add_storages
```

Verify it:

```sh
ceph osd pool get <pool> size
ceph osd pool get <pool> min_size
pvesm status
```

To change an existing pool instead:

```sh
ceph osd pool set <pool> size 2
ceph osd pool set <pool> min_size 1
```

PVE explicitly warns against `min_size 1`: a replicated pool with only one replica allows I/O and can lead to data loss, incomplete placement groups, or unfound objects. All three nodes run MONs, so one MON can fail without losing quorum, but the pool still has only one surviving replica after an OSD host fails. Add a third OSD host if a host failure must keep full redundancy, or accept the degraded and data-loss risk.

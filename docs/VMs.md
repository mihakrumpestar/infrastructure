# VMs

```sh
virt-manager -c 'qemu+ssh://server-03/system'
```

## ISOs

```sh
cd /var/lib/libvirt/iso
```

### Windows

Just RDP optimization: https://www.reddit.com/r/sysadmin/comments/fv7d12/pushing_remote_fx_to_its_limits/

Nvidia: Tesla GPU driver (16.10 is the last version that works <https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.10/539.28_grid_win10_win11_server2019_server2022_dch_64bit_international.exe>): <https://cloud.google.com/compute/docs/gpus/grid-drivers-table?authuser=0#windows_drivers>. Or this guide: <https://github.com/JingShing/How-to-use-tesla-p40>,https://linustechtips.com/topic/1496913-can-i-enable-wddm-on-a-tesla-p40/page/2/ (do not use `EnableMsHybrid` if this is the only gpu in system)

```sh
wget https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/latest-virtio/virtio-win.iso
```

Install "Virtual Display Driver", eg.: https://github.com/VirtualDrivers/Virtual-Display-Driver/releases

https://github.com/VirtualDrivers/Virtual-Display-Driver/wiki/How-to-configure-the-driver

To move apps from one screen to another use shortcut: `Windows + Shift + Left Arrow`

Install Sunshine: https://github.com/LizardByte/Sunshine/releases

Manage it: https://localhost:47990/

### OpenWRT

[Guide](https://openwrt.org/docs/guide-user/installation/openwrt_x86)

```sh

wget https://downloads.openwrt.org/releases/24.10.0/targets/x86/64/openwrt-24.10.0-x86-64-generic-ext4-combined.img.gz

# Unpack image
gunzip openwrt-*.img.gz

qemu-img convert -f raw -O qcow2 openwrt.img openwrt.qcow2
qemu-img resize openwrt.qcow2 8G

```

Initial setup:

```sh
# Set password
passwd

# Set LAN IP
uci set network.lan.ipaddr='x.x.x.x'
uci commit network
/etc/init.d/network restart
```

# VMs

```sh
virt-manager -c 'qemu+ssh://server-03/system'
```

## ISOs

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

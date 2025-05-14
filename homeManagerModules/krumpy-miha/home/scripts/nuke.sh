#!/usr/bin/env bash

echo "

Disable internet:

# nmcli networking off # If using NetworkManager

List drives:

# lsblk

or 

# sudo fdisk -l

or

# df -h

-----------------------------------------------------------------------------------------------------------------

Zero-fill the disk by writing a zero byte to every addressable location on the disk using the /dev/zero stream. 

# dd if=/dev/zero of=/dev/sdX bs=4096 status=progress

or the /dev/urandom stream:

# dd if=/dev/urandom of=/dev/sdX bs=4096 status=progress

"
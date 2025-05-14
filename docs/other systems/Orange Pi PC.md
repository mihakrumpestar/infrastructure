# Orange Pi PC

This is a print and scanning server.

[IMG link](https://www.armbian.com/orange-pi-pc/)

## Setup

### System utils

```bash
sudo apt install -y btop
```

### Set password

```bash
passwd
```

### Set Up Passwordless Sudo for Admin User

Create a sudoers file for the admin user:

```bash
sudo tee /etc/sudoers.d/admin > /dev/null << EOL
admin ALL=(ALL) NOPASSWD: ALL
EOL

sudo chmod 0440 /etc/sudoers.d/admin
```

## Wifi drivers

```bash
sudo apt install -y hostapd 

sudo apt install -y linux-headers-generic
sudo apt install -y bc build-essential git

git clone https://github.com/wandercn/RTL8188GU.git
cd RTL8188GU/8188gu-1.0.1

sudo make

sudo make install

```

### Set Up Static IP

Create a new network interface configuration file:

```bash
sudo tee /etc/netplan/01-eth.yaml > /dev/null << EOL
network:
  version: 2
  renderer: networkd
  ethernets:
    end0:
      dhcp4: no
      addresses:
        - 10.0.100.70/16
      routes:
        - to: default
          via: 10.0.0.1
      nameservers:
        addresses: [10.0.100.95]
EOL

sudo chmod 600 /etc/netplan/01-eth.yaml

sudo rm /etc/netplan/10-dhcp-all-interfaces.yaml # Remove the old one

sudo netplan generate
sudo netplan apply

# ls /run/systemd/network/ # Validate generated network conf
```

### Firewall

```bash
sudo apt update && sudo apt install -y ufw

sudo ufw default deny incoming
sudo ufw default allow outgoing

sudo ufw allow 22 # SSH
sudo ufw allow 5353/udp # Avahi
sudo ufw allow 60000:65535 # IPP-USB

sudo ufw status verbose
sudo ufw reload

sudo ufw enable
```

### Configure SSH

Add Public Key:

```bash
sudo mkdir -p /home/admin/.ssh
sudo tee -a /home/admin/.ssh/authorized_keys > /dev/null << EOL
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKcjctvM6JIgxtsRIBZlIxxKpuWZgS8j9rA9deajQd0+ VMs
EOL
sudo chmod 700 /home/admin/.ssh
sudo chmod 600 /home/admin/.ssh/authorized_keys
```

Create a new SSH config file:

```bash
sudo tee /etc/ssh/sshd_config > /dev/null << EOL
Port 22
PermitRootLogin no
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding yes
PrintMotd yes
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server

MaxAuthTries 20
EOL

sudo systemctl restart ssh
```

### Set up locale

If not correct already:

```bash
sudo dpkg-reconfigure locales
```

### Set up keyboard

Configure the keyboard layout:

```bash
sudo tee /etc/default/keyboard > /dev/null << EOL
XKBMODEL="pc105"
XKBLAYOUT="si"
XKBVARIANT=""
XKBOPTIONS=""

BACKSPACE="guess"
EOL

sudo dpkg-reconfigure -f noninteractive keyboard-configuration
sudo service keyboard-setup restart
```

### Time/timezone

```bash
timedatectl

sudo timedatectl set-timezone Europe/Ljubljana
```

### Set Up Print/scan server

[Docs](https://man.archlinux.org/man/extra/ipp-usb/ipp-usb.8.en).

```bash
lsusb | grep HP

sudo apt install -y ipp-usb avahi-autoipd libnss-mdns

sudo sed -i 's/interface = loopback/interface = all/' /etc/ipp-usb/ipp-usb.conf
sudo sed -i 's/ipv6 = enable/ipv6 = disable/' /etc/ipp-usb/ipp-usb.conf

sudo ipp-usb check

sudo tee /usr/share/ipp-usb/quirks/custom.conf > /dev/null << EOL
[HP Deskjet 5520 series]
  disable-fax = true
EOL
# http-connection = keep-alive # Fails
# buggy-ipp-responses = sanitize # Fails

# usb-max-interfaces = 1 # Device initialization timed out
# usb-max-interfaces = 2 # Device initialization timed out
#  # Device initialization timed out
# buggy-ipp-responses = allow
# buggy-ipp-responses = reject
# init-reset = hard
# request-delay = 5000

sudo systemctl restart ipp-usb

sudo ipp-usb status

# Logs
sudo less /var/log/ipp-usb/

#Web UI
http://10.0.100.70:60000
```

Debug:

```bash
scanimage -L

avahi-browse -a
avahi-browse -art | less

# Printing services
avahi-browse -rt _ipp._tcp

# Scanning services
avahi-browse -rt _uscan._tcp
```

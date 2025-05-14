# Nvidia driver

Make sure GPU is even detected:

```bash
lspci -nn | egrep -i "3d|display|vga"
sudo lshw -c display
```

Install driver (server version did not work, but regular did):

```bash
sudo add-apt-repository ppa:graphics-drivers/ppa
sudo apt update
sudo ubuntu-drivers autoinstall
sudo reboot
```

Test driver:

```bash
nvidia-smi
```

[Docker support](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html):

```bash
sudo apt-get update \
    && sudo apt-get install -y nvidia-container-toolkit-base
nvidia-ctk --version

sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
grep "  name:" /etc/cdi/nvidia.yaml

sudo systemctl restart docker
```

Test Docker support:

```bash
sudo docker run -it --rm --gpus all ubuntu nvidia-smi
```

Uninstall:

```bash
# sudo apt autoremove nvidia* --purge
```

## Nvidia vGPU

```bash
https://www.servethehome.com/how-to-pass-through-pcie-nics-with-proxmox-ve-on-intel-and-amd/
https://pve.proxmox.com/wiki/NVIDIA_vGPU_on_Proxmox_VE_7.x
https://github.com/mdevctl/mdevctl
https://gitlab.com/polloloco/vgpu-proxmox
https://gitea.publichub.eu/oscar.krause/fastapi-dls
https://github.com/mbilker/vgpu_unlock-rs
```

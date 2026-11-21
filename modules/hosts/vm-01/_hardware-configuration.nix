{
  lib,
  modulesPath,
  ...
}:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  # KVM guest: virtio for the disk and NIC, AHCI and USB as board fallbacks.
  boot.initrd.availableKernelModules = [
    "uhci_hcd"
    "ehci_pci"
    "ahci"
    "virtio_pci"
    "sr_mod"
    "virtio_blk"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}

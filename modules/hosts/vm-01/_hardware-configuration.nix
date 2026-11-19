{
  lib,
  modulesPath,
  ...
}:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  # KVM guest: virtio for the disk and NIC, ata_piix as the SATA fallback a
  # provider may hand out instead.
  boot.initrd.availableKernelModules = [
    "ata_piix"
    "virtio_pci"
    "virtio_blk"
    "sr_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}

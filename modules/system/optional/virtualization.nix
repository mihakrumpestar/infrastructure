{ ... }:
{
  den.aspects.virtualization = {
    nixos =
      { pkgs, ... }:
      {
        # IOMMU support for PCI passthrough
        boot = {
          kernelParams = [
            "amd_iommu=on"
            "intel_iommu=on"
            "iommu=pt"
            "rd.driver.pre=vfio-pci"
          ];

          # Nested virtualization
          # cat /sys/module/kvm_amd/parameters/nested
          extraModprobeConfig = ''
            options kvm_amd nested=1
            options kvm_intel nested=1
            options kvm_intel emulate_invalid_guest_state=0
            options kvm ignore_msrs=1
          '';
        };

        # Enable virtualization

        environment.systemPackages = with pkgs; [
          qemu_kvm
          #qemu_full this one uses RBD, which pulls ceph as dep
          cdrkit # For genisoimage and other tools
        ];

        virtualisation = {
          # spice-gtk USB redirection for virt-manager VM viewers
          spiceUSBRedirection.enable = true;

          libvirtd = {
            enable = true;
            qemu.swtpm.enable = true; # TPM emulation for VMs (Win11 needs it)
          };
        };

        # Default NAT bridge virbr0 is allowed by the libvirtd module default.
        programs.virt-manager.enable = true;
      };
  };
}

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

        /*
          virtualisation = {
            spiceUSBRedirection.enable = true;

            libvirtd = {
              enable = true;
              qemu.swtpm.enable = true;
              allowedBridges = ["virbr0" "br0" "br1"];
            };
          };

          system.activationScripts.makeDefaultPool = lib.stringAfter ["var"] ''
            mkdir -p /var/lib/libvirt/images
            mkdir -p /var/lib/libvirt/iso
          '';

          programs.virt-manager.enable = true;
          # Add required users to group "libvirtd"
        */
      };
  };
}

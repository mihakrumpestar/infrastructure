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

        # NixOS nftables-based firewall drops DHCP/DNS on libvirt's default
        # NAT bridge unless the interface is trusted (nixpkgs #437920).
        # The libvirtd module only auto-allows virbr0 for iptables setups.
        networking.firewall.trustedInterfaces = [ "virbr0" ];
        programs.virt-manager.enable = true;
      };
  };
}

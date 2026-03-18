{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  config = mkIf (config.my.hostSubType != "kiosk") {
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
    */

    #services.cockpit = {
    #  enable = true;
    #  port = 9090;
    #  openFirewall = true;
    #};

    # Enable containers
    virtualisation = {
      docker = {
        enable = true;
        package = pkgs.docker_28; # v29 is just more broken with every single release
        daemon = {
          settings = {
            log-level = "warn"; # "debug"|"info"|"warn"|"error"|"fatal" (default "info")
            live-restore = true;
            registry-mirrors = ["https://mirror.gcr.io"];
          };
        };
      };
    };

    # IMPORTANT: Add required users to groups ["libvirtd" "docker"]
  };
}

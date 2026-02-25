{
  config,
  nixvirt,
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
      extraModprobeConfig = ''
        options kvm_amd nested=1
        options kvm_intel nested=1

        options kvm_intel emulate_invalid_guest_state=0
        options kvm ignore_msrs=1
      ''; # Nested virtualization
      # Validate: cat /sys/module/kvm_amd/parameters/nested
    };

    system.activationScripts.makeDefaultPool = lib.stringAfter ["var"] ''
      mkdir -p /var/lib/libvirt/images
      mkdir -p /var/lib/libvirt/iso
    '';

    # Enable virtualization
    virtualisation = {
      spiceUSBRedirection.enable = true;

      libvirtd = {
        enable = true;
        qemu.swtpm.enable = true;
        allowedBridges = ["virbr0" "br0" "br1"];
      };

      libvirt = mkIf (config.my.hostType == "server" && config.my.hostSubType != "vm") {
        enable = true; # Enables libvirtd too
        connections."qemu:///system" = {
          pools = [
            {
              active = true;
              definition = nixvirt.lib.pool.writeXML {
                name = "default";
                type = "dir";
                uuid = "5a20ff16-b3f0-472e-886f-9158afe12b6c";
                target = {
                  path = "/var/lib/libvirt/images";
                  permissions = {
                    mode = {
                      octal = "0755";
                    };
                    owner = {
                      uid = 1000;
                    };
                    group = {
                      gid = 100;
                    };
                  };
                };
              };
            }
            {
              active = true;
              definition = nixvirt.lib.pool.writeXML {
                name = "iso";
                type = "dir";
                uuid = "5f67b3f0-148e-4c7d-ae37-fa82e3a44d0d";
                target.path = "/var/lib/libvirt/iso";
              };
            }
          ];

          networks = [
            {
              active = false;
              definition = nixvirt.lib.network.writeXML {
                name = "virbr0";
                uuid = "6aec104f-3126-458a-918e-54e2b9e66b18";
                forward.mode = "nat";
                bridge.name = "virbr0";
                mac.address = "52:54:00:1f:7b:b0";
                ip = {
                  address = "192.168.122.1";
                  netmask = "255.255.255.0";
                  dhcp = {
                    range = {
                      start = "192.168.122.2";
                      end = "192.168.122.254";
                    };
                  };
                };
              };
            }
            {
              active = true;
              definition = nixvirt.lib.network.writeXML {
                name = "br0";
                uuid = "35274393-898d-4e52-98ae-dcc451949088";
                bridge.name = "br0";
                forward.mode = "bridge";
              };
            }
          ];
        };
      };
    };

    programs.virt-manager.enable = true;

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
            insecure-registries = ["10.0.30.10:30010" "10.0.30.20:30010" "10.0.30.30:30010"];
          };
        };
      };
    };

    # IMPORTANT: Add required users to groups ["libvirtd" "docker"]
  };
}

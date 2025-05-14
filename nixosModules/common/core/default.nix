{
  config,
  pkgs,
  lib,
  ...
}:
with lib; {
  imports = [
    ./boot.nix
    ./console.nix
    ./disks.nix
    ./networking.nix
    ./nix.nix
    ./secrets.nix
    ./shell.nix
  ];

  options.my = {
    client = {
      enable = mkEnableOption "If the system is a client";
      laptop.enable = mkEnableOption "If client is a laptop";
    };
    server = {
      enable = mkEnableOption "If the system is a server";
    };
  };

  config = {
    # System packages
    environment.systemPackages = with pkgs; [
      usbutils # For lsusb
      memtester # Test: memtester 60G
      smartmontools # Has: smartctl
      nvme-cli # Has: nvme
      dmidecode
      pciutils # Has: lspci
      zenstates # https://github.com/r4m0n/ZenStates-Linux
    ];

    # SSH
    services = {
      sshd.enable = true;
      openssh = {
        openFirewall = true;
        ports = [
          22222
        ];
        settings = {
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
        };
        extraConfig = "MaxAuthTries 20";
      };

      # Time synchronization
      ntpd-rs = {
        enable = true; # Check: ntp-ctl status
        settings = {
          source = mkDefault {
            address = "nts.netnod.se";
            mode = "nts";
          };
          observability = {
            log-level = "warn";
          };
        };
      };

      # Firmware updates (client deamon, but updates only apply upon manual request)
      fwupd.enable = true; # Devices: https://fwupd.org/lvfs/devices/
      # Usage:
      # fwupdmgr get-devices
      # fwupdmgr refresh
      # fwupdmgr get-updates
      # fwupdmgr update
    };

    users = {
      mutableUsers = false; # Users are strictly managed by NixOS
      users = mkMerge [
        {
          root = {
            openssh.authorizedKeys.keyFiles = [
              (pkgs.writeText "ssh_authorized_keys" config.my.store-secrets.secrets."ssh_authorized_keys")
            ];
          };
        }
        # Allow physical access to server
        (mkIf config.my.server.enable {
          admin = {
            isNormalUser = true;
            isSystemUser = false;
            linger = true;
            extraGroups = [
              "wheel" # Add to sudoers
              "docker"
              "libvirtd"
              "kvm"
              "tss"
            ];
            hashedPasswordFile = config.sops.secrets.admin_hashedPassword.path; # Generate using: mkpasswd
            openssh.authorizedKeys.keys = [];
          };
        })
      ];
    };

    sops.secrets = mkIf config.my.server.enable {
      admin_hashedPassword.neededForUsers = true;
    };

    security.sudo = {
      extraConfig = ''
        Defaults  lecture="never"
      '';
      wheelNeedsPassword = !config.my.server.enable;
    };

    nix.settings.trusted-users = [
      "root"
      "@wheel"
    ];

    security.polkit = {
      enable = true;
      # debug = true;
      extraConfig = ''
        /* Log authorization checks. */
        polkit.addRule(function(action, subject) {
          polkit.log("user " +  subject.user + " is attempting action " + action.id + " from PID " + subject.pid);
        });
      '';
    };

    # Timezone
    time.timeZone = "Europe/Ljubljana";
  };
}

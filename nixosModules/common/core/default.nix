{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  store-secrets = config.my.store-secrets.secrets;
in {
  imports = [
    ./console.nix
    ./disks.nix
    ./networking.nix
    ./nix.nix
    ./secrets.nix
    ./shell.nix
    ./style.nix
  ];

  options.my = {
    hostType = mkOption {
      type = types.enum [false "client" "server"];
      default = false;
      description = "What type is the host";
    };
    hostSubType = mkOption {
      type = types.enum [false "kiosk"];
      default = false;
      description = "What subtype is the host";
    };
  };

  config = {
    boot = {
      kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

      kernelModules =
        if config.hardware.cpu.amd.updateMicrocode
        then ["msr"] # Required for zenstates
        else [];

      # Optimizations
      kernel.sysctl = {
        # https://www.cockroachlabs.com/docs/stable/recommended-production-settings
        #"vm.swappiness" = 0; # Memory swapping required to be minimal by Cockroachdb
      };
    };

    security = {
      sudo = {
        extraConfig = ''
          Defaults  lecture="never"
        '';
        wheelNeedsPassword = config.my.hostType != "server";
      };
      polkit = {
        enable = true;
        # debug = true;
        extraConfig = ''
          /* Log authorization checks. */
          polkit.addRule(function(action, subject) {
            polkit.log("user " +  subject.user + " is attempting action " + action.id + " from PID " + subject.pid);
          });
        '';
      };
      # Optimizations
      # https://www.cockroachlabs.com/docs/stable/recommended-production-settings
      pam.loginLimits = [
        {
          domain = "*";
          type = "-";
          item = "nofile";
          value = "unlimited";
        } # High or unlimited no. of open files required by Cockroachdb, verify: ulimit -n
      ];
    };

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
            openssh.authorizedKeys.keys = [
              store-secrets."ssh_authorized_keys".${config.my.hostType}
            ];
          };
        }
        # Allow physical access to server
        (mkIf (config.my.hostType == "server") {
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
            hashedPasswordFile = store-secrets."admin_hashedPassword"; # Generate using: mkpasswd
            openssh.authorizedKeys.keys = [];
          };
        })
      ];
    };

    nix.settings.trusted-users = [
      "root"
      "@wheel"
    ];

    # Timezone
    time.timeZone = "Europe/Ljubljana";
  };
}

{ ... }:
{
  den.aspects.core = {
    nixos =
      {
        lib,
        pkgs,
        ...
      }:
      {
        config = {
          boot = {
            kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

            # Pre-load modules for hot-pluggable devices at boot, because security.lockKernelModules
            # prevents loading kernel modules after the system is fully initialised.
            # Without this, USB drives, external disks, and optical drives won't be usable.
            kernelModules = [
              "usb_storage" # USB mass storage (BOT protocol)
              "uas" # USB Attached SCSI (faster, modern USB storage)
              "sd_mod" # SCSI disk driver (required by usb_storage/uas)
              "sr_mod" # SCSI CD/DVD ROM (optical drives via USB)
              "exfat" # exFAT filesystem (common on USB drives > 32GB and SD cards)
              "ntfs3" # NTFS filesystem (Windows drives, in-kernel driver)
              "udf" # UDF filesystem (optical media, some USB drives)
              "iso9660" # ISO 9660 filesystem (CD/DVD)
            ];

            supportedFilesystems = [
              "exfat"
              "ntfs"
              "udf"
              "iso9660"
            ];
          };

          security = {
            sudo.extraConfig = ''
              Defaults  lecture="never"
            '';

            polkit = {
              enable = true;
              #debug = true;

              # Log authorization checks.
              extraConfig = ''
                polkit.addRule(function(action, subject) {
                  polkit.log("user " +  subject.user + " is attempting action " + action.id + " from PID " + subject.pid);
                });
              '';
            };
            # Optimizations
            # https://www.cockroachlabs.com/docs/stable/recommended-production-settings
            # High or unlimited no. of open files required by Cockroachdb, verify: ulimit -n
            pam.loginLimits = [
              {
                domain = "*";
                type = "-";
                item = "nofile";
                value = "unlimited";
              }
            ];

            # Prevent loading kernel modules after start (should prevent nasty exploits of loading obscure modules)
            # Note that we have to load all needed ones therefore in config
            lockKernelModules = true;
          };

          environment.systemPackages = with pkgs; [
            usbutils # For lsusb
            memtester # Test: memtester 60G
            smartmontools # Has: smartctl
            nvme-cli # Has: nvme
            dmidecode
            pciutils # Has: lspci

            # System info
            cpu-x # CPU, GPU and motherboard info
          ];

          # Make some of the dynamically linked binaries work, that are not part of nix (eg. VSCode extensions, etc.)
          programs.nix-ld.enable = true;

          services = {
            # SSH
            sshd.enable = true;
            openssh = {
              openFirewall = true;
              ports = [ 22222 ];
              settings = {
                PasswordAuthentication = false;
                KbdInteractiveAuthentication = false;
              };
              extraConfig = "MaxAuthTries 20";
            };

            # Time synchronization
            # Check: ntp-ctl status
            ntpd-rs = {
              enable = true;
              settings = {
                source = [
                  {
                    address = "nts.netnod.se";
                    mode = "nts";
                  }
                ];
                observability = {
                  log-level = "warn";
                };
              };
            };

            # Firmware updates (client deamon, but updates only apply when run "fwupdmgr update")
            fwupd.enable = true; # Devices: https://fwupd.org/lvfs/devices/
            # Usage:
            # fwupdmgr get-devices
            # fwupdmgr refresh
            # fwupdmgr get-updates
            # fwupdmgr update
          };

          users = {
            mutableUsers = false; # Users are strictly managed by NixOS
            groups."users".gid = 100;
          };

          nix.settings.trusted-users = [
            "root"
            "@wheel"
          ];

          # logrotate does not have any log level on it's own, so we do it at service level
          systemd.services.logrotate.serviceConfig.LogLevelMax = "warning";
        };
      };
  };
}

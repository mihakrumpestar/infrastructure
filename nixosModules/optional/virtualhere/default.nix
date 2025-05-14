{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.virtualhere;
  virtualhere-client-gui = pkgs.callPackage ./gui.nix {};
  virtualhere-client-cli = pkgs.callPackage ./cli.nix {};
in {
  options.services.virtualhere = {
    enable = mkEnableOption "VirtualHere USB Client";

    enableGui = mkOption {
      type = types.bool;
      default = true;
      description = "Enable the VirtualHere GUI client and start it on user session";
    };

    enableCli = mkOption {
      type = types.bool;
      default = true;
      description = "Enable the VirtualHere CLI client and start it on user session";
    };

    runCliAsUser = mkOption {
      type = types.bool;
      default = true;
      description = "Run the VirtualHere CLI client as a user service";
    };
  };

  config = mkIf cfg.enable {
    # Create the virtualhere group
    users.groups.virtualhere = {};

    # Set permissions for the installed binaries
    security.sudo.extraRules = [
      {
        groups = ["virtualhere"];
        commands = [
          # No password required and preserve environment
          {
            # Not using  as we are calling sudo in the underlaying function
            command = "${virtualhere-client-gui}/bin/virtualhere-client-gui";
            options = [
              "NOPASSWD"
              "SETENV"
            ];
          }
          {
            command = "${virtualhere-client-cli}/bin/virtualhere-client-cli";
            options = [
              "NOPASSWD"
              "SETENV"
            ];
          }
          {
            command = "/run/current-system/sw/bin/virtualhere-client-gui";
            options = [
              "NOPASSWD"
              "SETENV"
            ];
          }
          {
            command = "/run/current-system/sw/bin/virtualhere-client-cli";
            options = [
              "NOPASSWD"
              "SETENV"
            ];
          }
        ];
      }
    ];

    # Install the packages
    environment.systemPackages = [
      virtualhere-client-gui
      virtualhere-client-cli
    ];

    # Tis one does not work for some reason
    # User session auto-start for GUI
    systemd = {
      user.services = {
        virtualhere-gui = {
          description = "VirtualHere GUI Client";
          wantedBy = ["default.target"];
          after = ["graphical.target"];
          serviceConfig = {
            ExecStart = "/run/wrappers/bin/sudo -E ${virtualhere-client-gui}/bin/virtualhere-client-gui";
            Restart = "on-failure";
          };

          # Only enable if the GUI is selected
          enable = cfg.enableGui;
        };

        # CLI as a user service
        virtualhere-cli = {
          description = "VirtualHere CLI Client";
          wantedBy = ["default.target"];
          after = ["graphical.target"];
          serviceConfig = {
            ExecStart = "/run/wrappers/bin/sudo -E ${virtualhere-client-cli}/bin/virtualhere-client-cli";
            Restart = "on-failure";
          };
          # Only enable if the CLI is selected and run as user
          enable = cfg.enableCli && cfg.runCliAsUser;
        };
      };

      # CLI as a system service
      services.virtualhere-cli = {
        description = "VirtualHere CLI Client (System Service)";
        after = ["network.target"];
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          ExecStart = "${virtualhere-client-cli}/bin/virtualhere-client-cli";
          Restart = "on-failure";
        };
        # Only enable if the CLI is selected and run as system service
        enable = cfg.enableCli && !cfg.runCliAsUser;
      };
    };

    # Required for GUI
    programs.nix-ld.enable = true;

    # Add usbip kernel module
    boot.extraModulePackages = with config.boot.kernelPackages; [usbip];
  };
}

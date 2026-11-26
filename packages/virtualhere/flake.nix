{
  description = "VirtualHere USB Client packages and modules";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    {
      self,
      nixpkgs,
    }:
    let
      version = "6.0.3";
      supportedSystems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgsForSystem =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = pkgsForSystem system;
        in
        {
          virtualhere-client-cli = pkgs.callPackage ./cli.nix { inherit version; };
          virtualhere-client-gui = pkgs.callPackage ./gui.nix { inherit version; };
          default = self.packages.${system}.virtualhere-client-gui;
        }
      );

      defaultPackage = forAllSystems (system: self.packages.${system}.default);

      nixosModules.default =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        with lib;
        let
          cfg = config.services.virtualhere;
          inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) virtualhere-client-gui;
          inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) virtualhere-client-cli;
          guiExe = getExe virtualhere-client-gui;
          cliExe = getExe virtualhere-client-cli;
          guiAutostart = "${guiExe} --start-minimized";
          userCli = cfg.enableCli && cfg.runCliAsUser;
          sudo = "${config.security.wrapperDir}/sudo -n --";
          userCommands =
            optionals cfg.enableGui [
              ''${guiExe} ""''
              guiAutostart
            ]
            ++ optional userCli ''${cliExe} ""'';
        in
        {
          options.services.virtualhere = {
            enable = mkEnableOption "VirtualHere USB clients and USB/IP kernel support";

            enableGui = mkOption {
              type = types.bool;
              default = false;
              description = "Allow members of the virtualhere group to launch the GUI and start it with their graphical session";
            };

            enableCli = mkOption {
              type = types.bool;
              default = false;
              description = "Start the VirtualHere CLI client as a user or system service";
            };

            runCliAsUser = mkOption {
              type = types.bool;
              default = true;
              description = "Run the CLI as a user service for members of the virtualhere group instead of as a system service";
            };
          };

          config = mkIf cfg.enable (mkMerge [
            {
              users.groups.virtualhere = { };

              # The clients require UID 0. Only grant the launch commands for enabled user services.
              security.sudo = {
                extraRules = optional (userCommands != [ ]) {
                  groups = [ "virtualhere" ];
                  runAs = "root";
                  commands = map (command: {
                    inherit command;
                    options = [
                      "NOPASSWD"
                      "NOSETENV"
                    ];
                  }) userCommands;
                };
                # Keep existing per-user settings and the GUI's display/session connection.
                extraConfig = ''
                  Defaults!${guiExe} env_reset, env_keep = "HOME DISPLAY XAUTHORITY WAYLAND_DISPLAY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS"
                  Defaults!${cliExe} env_reset, env_keep = "HOME"
                '';
              };

              environment.systemPackages = [
                virtualhere-client-gui
                virtualhere-client-cli
                pkgs.kmod
              ];

              boot.extraModulePackages = with config.boot.kernelPackages; [ usbip ];
              boot.kernelModules = [
                "vhci_hcd"
                "usbip_core"
              ];
            }

            (mkIf cfg.enableGui {
              systemd.user.services.virtualhere-gui = {
                description = "VirtualHere GUI Client";
                wantedBy = [ "graphical-session.target" ];
                after = [ "graphical-session.target" ];
                partOf = [ "graphical-session.target" ];
                serviceConfig = {
                  Type = "simple";
                  ExecStart = "${sudo} ${guiAutostart}";
                  Restart = "on-failure";
                };
                unitConfig = {
                  ConditionGroup = "virtualhere";
                };
              };
            })

            (mkIf userCli {
              systemd.user.services.virtualhere-cli = {
                description = "VirtualHere CLI Client";
                wantedBy = [ "default.target" ];
                after = [ "network.target" ];
                serviceConfig = {
                  ExecStart = "${sudo} ${cliExe}";
                  Restart = "on-failure";
                };
                unitConfig = {
                  ConditionGroup = "virtualhere";
                };
              };
            })

            (mkIf (cfg.enableCli && !cfg.runCliAsUser) {
              systemd.services.virtualhere-cli = {
                description = "VirtualHere CLI Client (System Service)";
                after = [ "network.target" ];
                wantedBy = [ "multi-user.target" ];
                serviceConfig = {
                  ExecStart = cliExe;
                  Restart = "on-failure";
                };
              };
            })
          ]);
        };
    };
}

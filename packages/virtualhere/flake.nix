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
          virtualhere-client-cli = pkgs.callPackage ./cli.nix { };
          virtualhere-client-gui = pkgs.callPackage ./gui.nix { inherit pkgs; };
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
        in
        {
          options.services.virtualhere = {
            enable = mkEnableOption "VirtualHere USB Client, user has to be in 'virtualhere' group";

            enableGui = mkOption {
              type = types.bool;
              default = false;
              description = "Enable the VirtualHere GUI client and start it on user session";
            };

            enableCli = mkOption {
              type = types.bool;
              default = false;
              description = "Enable the VirtualHere CLI client and start it on user session";
            };

            runCliAsUser = mkOption {
              type = types.bool;
              default = true;
              description = "Run the VirtualHere CLI client as a user service";
            };
          };

          config = mkIf cfg.enable (mkMerge [
            {
              users.groups.virtualhere = { };

              # The VirtualHere binary checks for UID 0 at startup and refuses to run otherwise.
              # sudo -E sets all UIDs to 0 (passing the check) while preserving the environment.
              security.sudo.extraRules = [
                {
                  groups = [ "virtualhere" ];
                  commands = [
                    {
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
                  ];
                }
              ];

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
                  ExecStart = "${config.security.wrapperDir}/sudo -E ${virtualhere-client-gui}/bin/virtualhere-client-gui --start-minimized";
                  Restart = "on-failure";
                };
                unitConfig = {
                  ConditionGroup = "virtualhere";
                };
              };
            })

            (mkIf cfg.enableCli (mkMerge [
              (mkIf cfg.runCliAsUser {
                systemd.user.services.virtualhere-cli = {
                  description = "VirtualHere CLI Client";
                  wantedBy = [ "default.target" ];
                  after = [ "network.target" ];
                  serviceConfig = {
                    ExecStart = "${config.security.wrapperDir}/sudo -E ${virtualhere-client-cli}/bin/virtualhere-client-cli";
                    Restart = "on-failure";
                  };
                  unitConfig = {
                    ConditionGroup = "virtualhere";
                  };
                };
              })
              (mkIf (!cfg.runCliAsUser) {
                systemd.services.virtualhere-cli = {
                  description = "VirtualHere CLI Client (System Service)";
                  after = [ "network.target" ];
                  wantedBy = [ "multi-user.target" ];
                  serviceConfig = {
                    ExecStart = "${virtualhere-client-cli}/bin/virtualhere-client-cli";
                    Restart = "on-failure";
                  };
                };
              })
            ]))
          ]);
        };
    };
}

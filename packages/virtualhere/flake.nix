{
  description = "VirtualHere USB Client packages and modules";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    supportedSystems = ["x86_64-linux"];
    forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    pkgsForSystem = system: import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
  in {
    packages = forAllSystems (system: let
      pkgs = pkgsForSystem system;
    in {
      virtualhere-client-cli = pkgs.callPackage ./cli.nix {};
      virtualhere-client-gui = pkgs.callPackage ./gui.nix {inherit pkgs;};
      default = self.packages.${system}.virtualhere-client-gui;
    });

    defaultPackage = forAllSystems (system: self.packages.${system}.default);

    nixosModules.default = {
      config,
      lib,
      pkgs,
      ...
    }:
      with lib; let
        cfg = config.services.virtualhere;
        inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) virtualhere-client-gui;
        inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) virtualhere-client-cli;
      in {
        options.services.virtualhere = {
          enable = mkEnableOption "VirtualHere USB Client, user has to be in 'virtualhere' group, to not require sudo password";

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
          users.groups.virtualhere = {};

          security.sudo.extraRules = [
            {
              groups = ["virtualhere"];
              commands = [
                {
                  command = "${virtualhere-client-gui}/bin/virtualhere-client-gui";
                  options = ["NOPASSWD" "SETENV"];
                }
                {
                  command = "${virtualhere-client-cli}/bin/virtualhere-client-cli";
                  options = ["NOPASSWD" "SETENV"];
                }
                {
                  command = "/run/current-system/sw/bin/virtualhere-client-gui";
                  options = ["NOPASSWD" "SETENV"];
                }
                {
                  command = "/run/current-system/sw/bin/virtualhere-client-cli";
                  options = ["NOPASSWD" "SETENV"];
                }
              ];
            }
          ];

          environment.systemPackages = [
            virtualhere-client-gui
            virtualhere-client-cli
          ];

          systemd = {
            user.services = {
              virtualhere-gui = {
                description = "VirtualHere GUI Client";
                wantedBy = ["default.target"];
                after = [
                  "graphical-session.target"
                  "plasma-plasmashell.service"
                ];
                serviceConfig = {
                  Type = "simple";
                  ExecStartPre = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 30); do [ -n \"$WAYLAND_DISPLAY\" ] && break; sleep 1; done'";
                  ExecStart = "/run/wrappers/bin/sudo -E ${virtualhere-client-gui}/bin/virtualhere-client-gui --start-minimized";
                  Restart = "on-failure";
                };
                unitConfig = {
                  ConditionGroup = "virtualhere";
                };
                enable = cfg.enableGui;
              };

              virtualhere-cli = {
                description = "VirtualHere CLI Client";
                wantedBy = ["default.target"];
                after = ["graphical-session.target"];
                serviceConfig = {
                  ExecStart = "/run/wrappers/bin/sudo -E ${virtualhere-client-cli}/bin/virtualhere-client-cli";
                  Restart = "on-failure";
                };
                unitConfig = {
                  ConditionGroup = "virtualhere";
                };
                enable = cfg.enableCli && cfg.runCliAsUser;
              };
            };

            services.virtualhere-cli = {
              description = "VirtualHere CLI Client (System Service)";
              after = ["network.target"];
              wantedBy = ["multi-user.target"];
              serviceConfig = {
                ExecStart = "${virtualhere-client-cli}/bin/virtualhere-client-cli";
                Restart = "on-failure";
              };
              enable = cfg.enableCli && !cfg.runCliAsUser;
            };
          };

          programs.nix-ld.enable = true;

          boot.extraModulePackages = with config.boot.kernelPackages; [usbip];
        };
      };
  };
}

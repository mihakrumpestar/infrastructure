{
  inputs,
  den,
  ...
}:
{
  imports = [ inputs.den.flakeModule ];

  den.hosts.x86_64-linux = {
    personal-workstation = {
      includes = [ den.aspects.personal-workstation ];
      users.krumpy-miha.classes = [ "homeManager" ];
    };

    personal-laptop = {
      includes = [ den.aspects.personal-laptop ];
      users.krumpy-miha.classes = [ "homeManager" ];
    };

    server-01 = {
      includes = [ den.aspects.server-01 ];
      users.admin = { };
    };

    server-03 = {
      includes = [ den.aspects.server-03 ];
      users.admin = { };
    };

    personal-vps-02 = {
      includes = [ den.aspects.personal-vps-02 ];
      users.admin = { };
    };

    kiosk = {
      includes = [ den.aspects.kiosk ];
      users.kiosk.classes = [ "homeManager" ];
    };
  };

  den.default = {
    includes = [
      den.batteries.hostname
      den.batteries.define-user

      den.aspects.core
      den.aspects.shell
      den.aspects.disks
      den.aspects.impermanence
      den.aspects.networking
      den.aspects.secrets
      den.aspects.nix
      den.aspects.locale
      den.aspects.style
    ];

    nixos =
      { config, ... }:
      {
        # For nixd to work properly
        nix.nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];

        system.stateVersion = config.system.nixos.release;

        nixpkgs.overlays = [
          inputs.nur.overlays.default
          inputs.nix-vscode-extensions.overlays.default
          (_: prev: {
            consul-cni = inputs.consul-cni.packages.${prev.stdenv.hostPlatform.system}.default;
            tix = inputs.tix.packages.${prev.stdenv.hostPlatform.system}.default;
          })
        ];

        imports = [
          inputs.disko.nixosModules.disko
          inputs.impermanence.nixosModules.impermanence
          inputs.agenix.nixosModules.default
          inputs.agenix-rekey.nixosModules.default
          inputs.lanzaboote.nixosModules.lanzaboote
          inputs.stylix.nixosModules.stylix
          inputs.nix-index-database.nixosModules.default
          inputs.virtualhere.nixosModules.default
          inputs.home-manager.nixosModules.home-manager
        ];

        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          backupFileExtension = "backup";
          sharedModules = [
            inputs.plasma-manager.homeModules.plasma-manager
            inputs.nix-index-database.homeModules.default
            inputs.agenix.homeManagerModules.default
            inputs.agenix-rekey.homeManagerModules.default
            inputs.mutable-file.homeModules.default
            (
              { osConfig, ... }:
              {
                home.stateVersion = osConfig.system.nixos.release;
              }
            )
          ];
        };
      };
  };
}

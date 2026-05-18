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
      users.krumpy-miha = {
        classes = [ "homeManager" ];
        includes = [
          den.aspects.krumpy-miha
          den.aspects.hm-common
          den.aspects.ssh
          den.aspects.git
          den.aspects.web-browser
          den.aspects.storage
          den.aspects.home-apps
          den.aspects.ide
          den.aspects.llm
          den.aspects.password-manager
          den.aspects.clipboard
          den.aspects.autostart
          den.aspects.scripts
          den.aspects.backup
          den.aspects.dead-mens-switch
        ];
      };
    };

    personal-laptop = {
      includes = [ den.aspects.personal-laptop ];
      users.krumpy-miha = {
        classes = [ "homeManager" ];
        includes = [
          den.aspects.krumpy-miha
          den.aspects.hm-common
          den.aspects.ssh
          den.aspects.git
          den.aspects.web-browser
          den.aspects.storage
          den.aspects.home-apps
          den.aspects.ide
          den.aspects.llm
          den.aspects.password-manager
          den.aspects.clipboard
          den.aspects.autostart
          den.aspects.scripts
        ];
      };
    };

    server-01 = {
      includes = [ den.aspects.server-01 ];
      users.admin = { };
    };

    server-03 = {
      includes = [ den.aspects.server-03 ];
      users.admin = { };
    };

    vps-02 = {
      includes = [ den.aspects.vps-02 ];
      users.admin = { };
    };

    kiosk = {
      includes = [ den.aspects.kiosk ];
      users.kiosk = {
        classes = [ "homeManager" ];
        includes = [
          den.aspects.kiosk-user
          den.aspects.hm-common
          den.aspects.kiosk-browser
          den.aspects.kiosk-brightness
        ];
      };
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
      den.aspects.defaults
      den.aspects.style
      den.aspects.hm-options
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
            zen-browser = inputs.zen-browser.packages.${prev.stdenv.hostPlatform.system}.default;
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
            inputs.zen-browser.homeModules.beta
            inputs.nix-index-database.homeModules.default
            inputs.agenix.homeManagerModules.default
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

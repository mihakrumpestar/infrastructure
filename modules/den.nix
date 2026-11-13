{
  inputs,
  den,
  ...
}:
{
  imports = [
    inputs.den.flakeModule
  ];

  den.hosts.x86_64-linux = {
    personal-workstation = {
      includes = [ den.aspects.personal-workstation ];
      users.krumpy-miha.classes = [ "homeManager" ];
    };

    personal-laptop = {
      includes = [ den.aspects.personal-laptop ];
      users.krumpy-miha.classes = [ "homeManager" ];
    };

    mihakrumpestar-work-laptop = {
      includes = [ den.aspects.mihakrumpestar-work-laptop ];
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
      users.public-user.classes = [ "homeManager" ];
    };
  };

  den = {
    schema.host.includes = [ den.batteries.user-aspects ];
    default = {
      includes = [
        den.batteries.hostname
        den.batteries.define-user
        den.batteries.host-aspects

        den.aspects.core
        den.aspects.shell
        den.aspects.disks
        den.aspects.impermanence
        den.aspects.networking
        den.aspects.secrets
        den.aspects.nix
        den.aspects.nix-cache
        den.aspects.locale
        den.aspects.style
      ];

      nixos =
        { config, ... }:
        {
          # For nixpkgs.expr to work properly in VSCode extension
          nix.settings.nix-path = [ "nixpkgs=${inputs.nixpkgs}" ];

          # In regular setups this would be a hardcoded version string (e.g. "26.11"), but in my case, it is whatever the latest version is.
          # This is ment to gatekeep applications such as DBs, that don't have automatic migrations on major version updates, from being automatically
          # updated on nixpkgs input updates; since this will silently keep old versions forever, you should use discrete packages, that have version in package name.
          # Hopefully this will be replaced/removed in the future.
          system.stateVersion = config.system.nixos.release;

          nixpkgs.overlays = [
            inputs.nur.overlays.default
            inputs.nix-vscode-extensions.overlays.default
            inputs.obsidian-extensions.overlays.default
            (_: prev: {
              consul-cni = inputs.consul-cni.packages.${prev.stdenv.hostPlatform.system}.default;
              github-desktop = inputs.github-desktop.packages.${prev.stdenv.hostPlatform.system}.default;
              # The weekly nixpkgs input predates cf; multiverse's store-path
              # index serves the Hydra-built package without evaluating nixpkgs.
              cf = inputs.multiverse.legacyPackages.${prev.stdenv.hostPlatform.system}.fast.latest.cf;
              # weekly moved peewee to 4.x before aw-core stopped pinning 3.*, so
              # python3Packages.aw-core fails its runtime deps check and takes
              # activitywatch (and home-manager) with it. Hydra's build of the
              # same version substitutes, so serve that instead of evaluating.
              activitywatch =
                inputs.multiverse.legacyPackages.${prev.stdenv.hostPlatform.system}.fast.latest.activitywatch;
              # OpenChamber requires OpenCode to be certain version, taking it from there keeps the pair in lockstep instead
              # of chasing nixpkgs weekly
              opencode = inputs.openchamber.packages.${prev.stdenv.hostPlatform.system}.opencode-cli;
              # Fleet tooling from the nomadx pin: the agent package and the
              # CLI, available everywhere as pkgs.nomad / pkgs.nomadx.
              nomad = inputs.nomadx.packages.${prev.stdenv.hostPlatform.system}.nomad;
              nomadx = inputs.nomadx.packages.${prev.stdenv.hostPlatform.system}.nomadx;
              # Admin CLI for the NetBird management API. Distinct from
              # pkgs.netbird, which is the client daemon/agent.
              netbird-manage = inputs.netbird-manage.packages.${prev.stdenv.hostPlatform.system}.default;
            })
          ];

          imports = [
            inputs.disko.nixosModules.disko
            inputs.impermanence.nixosModules.impermanence
            inputs.agenix.nixosModules.default
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
            overwriteBackup = true;
            sharedModules = [
              inputs.plasma-manager.homeModules.plasma-manager
              inputs.nix-index-database.homeModules.default
              inputs.agenix.homeManagerModules.default
              inputs.mutable-file.homeModules.default
              inputs.keepass-config-gen.homeManagerModules.ssh-config-gen
              inputs.keepass-config-gen.homeManagerModules.remmina-config-gen
              inputs.keepass-config-gen.homeManagerModules.gh-config-gen
              (
                { osConfig, ... }:
                {
                  home.stateVersion = osConfig.system.nixos.release; # Dangerous, see system.stateVersion comment
                }
              )
            ];
          };
        };
    };
  };
}

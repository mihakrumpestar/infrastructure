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

  den.default = {
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
          inputs.llm-agents.overlays.shared-nixpkgs
          (_: prev: {
            consul-cni = inputs.consul-cni.packages.${prev.stdenv.hostPlatform.system}.default;
            github-desktop = inputs.github-desktop.packages.${prev.stdenv.hostPlatform.system}.default;
            # The weekly nixpkgs input predates cf; multiverse's store-path
            # index serves the Hydra-built package without evaluating nixpkgs.
            cf = inputs.multiverse.legacyPackages.${prev.stdenv.hostPlatform.system}.fast.latest.cf;
            # Fleet tooling from the nomadx pin: the agent package and the
            # CLI, available everywhere as pkgs.nomad / pkgs.nomadx.
            nomad = inputs.nomadx.packages.${prev.stdenv.hostPlatform.system}.nomad;
            nomadx = inputs.nomadx.packages.${prev.stdenv.hostPlatform.system}.nomadx;
          })
          # llm-agents ships OpenCode v2 as `opencode2`, so rename the binary and
          # mainProgram for the home-manager module and service. The old "no auth
          # serve" blocker no longer exists: v2 `serve` always requires basic auth.
          # The wrapper keeps the version in its name so lib.getVersion reports
          # 2.1.4, which is what makes the home-manager module use v2 behaviour.
          (
            final: prev:
            let
              opencode2 = final.llm-agents.opencode2;
            in
            {
              opencode =
                prev.runCommand "opencode-${opencode2.version}"
                  {
                    inherit (opencode2) version;
                    nativeBuildInputs = [ prev.makeWrapper ];
                    meta = opencode2.meta // {
                      mainProgram = "opencode";
                    };
                  }
                  ''
                    mkdir -p $out/bin
                    makeWrapper ${opencode2}/bin/opencode2 $out/bin/opencode
                  '';
            }
          )
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
}

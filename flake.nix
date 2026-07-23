{
  description = "deployment flake";

  inputs = {

    # DeterminateSystems/nixpkgs-weekly updates weekly with 1 week cooldown period, to mitigate supply chain attacks
    nixpkgs.url = "https://flakehub.com/f/DeterminateSystems/nixpkgs-weekly/0.1"; # github:NixOS/nixpkgs/nixos-unstable

    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    den.url = "github:denful/den"; # Does not have nixpkgs
    import-tree.url = "github:denful/import-tree"; # Does not have nixpkgs

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    impermanence = {
      url = "github:mihakrumpestar/impermanence/fix-initrd-user-permissions"; # github:nix-community/impermanence
      inputs = {
        nixpkgs.follows = ""; # Only used for dev
        home-manager.follows = ""; # Only used for dev
      };
    };

    agenix = {
      # PR #353: fix agenix + userborn ordering (secrets before sysusers, chown after)
      # https://github.com/ryantm/agenix/pull/353
      url = "github:ryantm/agenix/pull/353/head";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    stylix = {
      url = "github:danth/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote"; # Using the master branch instead of recommended v1.0.0
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    openchamber = {
      url = "github:zms-dev/openchamber-flake/dev";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Experimental
    tix = {
      url = "github:JRMurr/tix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Local

    consul-cni.url = "./packages/consul-cni";

    mutable-file.url = "./lib/mutable-file";

    virtualhere = {
      url = "./packages/virtualhere";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Skills

    mattpocock-skills = {
      url = "github:mattpocock/skills";
      flake = false;
    };

    # Secrets

    infrastructure-secrets = {
      url = "git+file:../infrastructure-secrets";
      flake = false;
    };
  };

  outputs =
    inputs:
    let
      den =
        (inputs.nixpkgs.lib.evalModules {
          modules = [ (inputs.import-tree ./modules) ];
          specialArgs.inputs = inputs;
        }).config;
    in
    {
      inherit (den.flake) nixosConfigurations;
    };
}

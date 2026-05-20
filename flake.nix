{
  description = "deployment flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nur.url = "github:nix-community/NUR";
    den.url = "github:denful/den";
    import-tree.url = "github:denful/import-tree";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    impermanence = {
      url = "github:mihakrumpestar/impermanence/fix-initrd-user-permissions";
      inputs = {
        nixpkgs.follows = "";
        home-manager.follows = "";
      };
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix-rekey = {
      url = "github:oddlama/agenix-rekey";
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

    nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";

    # Experimental
    tix.url = "github:JRMurr/tix";

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
    { self, ... }@inputs:
    let
      den =
        (inputs.nixpkgs.lib.evalModules {
          modules = [ (inputs.import-tree ./modules) ];
          specialArgs.inputs = inputs;
        }).config;
    in
    {
      inherit (den.flake) nixosConfigurations;

      agenix-rekey = inputs.agenix-rekey.configure {
        userFlake = self;
        inherit (self) nixosConfigurations;
        darwinConfigurations = { };
        agePackage = p: p.age;
      };
    };
}

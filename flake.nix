{
  description = "deployment flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nur.url = "github:nix-community/NUR";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    impermanence = {
      url = "github:mihakrumpestar/impermanence/fix-initrd-user-permissions"; # "github:nix-community/impermanence";
      inputs = {
        nixpkgs.follows = "";
        home-manager.follows = "";
      };
    };

    agenix = {
      url = "github:ryantm/agenix";
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

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.0.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";

    # Local

    consul-cni.url = "./packages/consul-cni";

    mutable-file.url = "./home-modules/mutable-file";

    virtualhere = {
      url = "./packages/virtualhere";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {nixpkgs, ...} @ attrs: let
    vars = {
      secretsDir = ./infrastructure-secrets;

      networkConfig = {
        Gateway = ["10.0.0.1"];
        DNS = ["9.9.9.9" "1.1.1.1"];
      };
    };

    mkNixosConfiguration = {
      hostName,
      system,
    }:
      nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs =
          {
            inherit vars;
            inherit hostName;
          }
          // attrs;
        modules = [
          ./.
        ];
      };
  in {
    nixosConfigurations = {
      personal-workstation = mkNixosConfiguration {
        hostName = "personal-workstation";
        system = "x86_64-linux";
      };
      personal-laptop = mkNixosConfiguration {
        hostName = "personal-laptop";
        system = "x86_64-linux";
      };
      server-01 = mkNixosConfiguration {
        hostName = "server-01";
        system = "x86_64-linux";
      };
      server-03 = mkNixosConfiguration {
        hostName = "server-03";
        system = "x86_64-linux";
      };
      vps-02 = mkNixosConfiguration {
        hostName = "vps-02";
        system = "x86_64-linux";
      };
      kiosk = mkNixosConfiguration {
        hostName = "kiosk";
        system = "x86_64-linux";
      };
    };
  };
}

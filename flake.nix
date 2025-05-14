{
  description = "PC deployment flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    systems.url = "github:nix-systems/default";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    #agenix.url = "github:ryantm/agenix";
    #agenix-rekey.url = "github:oddlama/agenix-rekey";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    stylix = {
      url = "github:danth/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvirt = {
      url = "github:AshleyYakeley/NixVirt";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";

    nur.url = "github:nix-community/NUR";
  };

  outputs = {nixpkgs, ...} @ attrs: let
    system = "x86_64-linux";
    inherit (nixpkgs) lib;
    #pkgs = nixpkgs.legacyPackages.${system};

    vars = {
      secretsDir = ./infrastructure-secrets;
    };

    mkNixosConfiguration = {hostName}:
      lib.nixosSystem {
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
      };
      personal-laptop = mkNixosConfiguration {
        hostName = "personal-laptop";
      };
      server-03 = mkNixosConfiguration {
        hostName = "server-03";
      };
      test = mkNixosConfiguration {
        hostName = "test";
      };
    };
  };
}

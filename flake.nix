{
  description = "deployment flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nur.url = "github:nix-community/NUR";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
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

    zen-browser.url = "github:0xc000022070/zen-browser-flake";

    nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";
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
      kiosk = mkNixosConfiguration {
        hostName = "kiosk";
      };
    };
  };
}

{
  description = "deployment flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nur.url = "github:nix-community/NUR";

    flake-utils.url = "github:numtide/flake-utils";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:mihakrumpestar/agenix"; # "github:ryantm/agenix";
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

    opencode = {
      url = "github:anomalyco/opencode";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };

    nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";

    consul-cni-flake.url = "./packages/consul-cni";
  };

  outputs = {
    nixpkgs,
    flake-utils,
    consul-cni-flake,
    opencode,
    ...
  } @ attrs: let
    vars = {
      secretsDir = ./infrastructure-secrets;
    };

    mkNixosConfiguration = {
      hostName,
      system,
    }:
      nixpkgs.lib.nixosSystem rec {
        inherit system;
        specialArgs =
          {
            inherit vars;
            inherit hostName;

            inherit (consul-cni-flake.packages."${system}") consul-cni;
            inherit (opencode.packages."${system}") opencode;
          }
          // attrs;
        modules = [
          ./.
        ];
      };
  in
    {
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
        kiosk = mkNixosConfiguration {
          hostName = "kiosk";
          system = "x86_64-linux";
        };
      };
    }
    // flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      devShells.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          go-task
          pre-commit
          alejandra
          deadnix
          statix
        ];

        shellHook = ''
          pre-commit autoupdate
          pre-commit install

          task decrypt
        '';
      };
    });
}

{
  config,
  disko,
  agenix,
  stylix,
  home-manager,
  mutable-file,
  nur,
  nix-vscode-extensions,
  nixpkgs,
  zen-browser,
  nix-index-database,
  lanzaboote,
  virtualhere,
  vars,
  hostName,
  ...
}: {
  imports = [
    disko.nixosModules.disko
    agenix.nixosModules.default
    stylix.nixosModules.stylix
    nix-index-database.nixosModules.default
    home-manager.nixosModules.home-manager
    lanzaboote.nixosModules.lanzaboote
    virtualhere.nixosModules.default
    {
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        backupFileExtension = "backup";
        sharedModules = [
          zen-browser.homeModules.beta
          nix-index-database.homeModules.default
          agenix.homeManagerModules.default
          mutable-file.homeModules.default
          ({osConfig, ...}: {
            home.stateVersion = osConfig.system.nixos.release;
          })
          {
            imports = [
              ./homeManagerModules
              ./nixosModules/optional/store-secrets
            ];
          }
        ];
        extraSpecialArgs = {
          inherit vars hostName;
        };
      };
    }
    ./homeManagerModules/users # Users
    ./hosts # Per "host"
    ./nixosModules # Per "options"
  ];

  system.stateVersion = config.system.nixos.release;

  nixpkgs.overlays = [
    nur.overlays.default
    nix-vscode-extensions.overlays.default
  ];

  # For nixd to work properly
  nix.nixPath = ["nixpkgs=${nixpkgs}"];
}

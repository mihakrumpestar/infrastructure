{
  disko,
  agenix,
  stylix,
  home-manager,
  nur,
  nix-vscode-extensions,
  nixpkgs,
  zen-browser,
  nix-index-database,
  lanzaboote,
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
    {
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        backupFileExtension = "backup";
        sharedModules = [
          zen-browser.homeModules.beta
          nix-index-database.homeModules.default
          agenix.homeManagerModules.default
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

  nixpkgs.overlays = [
    nur.overlays.default
    nix-vscode-extensions.overlays.default
  ];

  # For nixd to work properly
  nix.nixPath = ["nixpkgs=${nixpkgs}"];
}

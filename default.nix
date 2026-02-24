{
  disko,
  agenix,
  stylix,
  home-manager,
  nur,
  nix-vscode-extensions,
  nixpkgs,
  nixvirt,
  zen-browser,
  nix-index-database,
  vars,
  hostName,
  ...
}: {
  imports = [
    disko.nixosModules.disko
    nixvirt.nixosModules.default
    agenix.nixosModules.default
    stylix.nixosModules.stylix
    nix-index-database.nixosModules.default
    home-manager.nixosModules.home-manager
    {
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        backupFileExtension = "backup";
        sharedModules = [
          nixvirt.homeModules.default
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

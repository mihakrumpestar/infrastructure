{
  config,
  disko,
  impermanence,
  agenix,
  stylix,
  home-manager,
  mutable-file,
  nur,
  plasma-manager,
  nix-vscode-extensions,
  nixpkgs,
  zen-browser,
  consul-cni,
  nix-index-database,
  lanzaboote,
  tix,
  virtualhere,
  vars,
  hostName,
  ...
}: {
  imports = [
    disko.nixosModules.disko
    impermanence.nixosModules.impermanence
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
          plasma-manager.homeModules.plasma-manager
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
    (_: prev: {
      zen-browser = zen-browser.packages.${prev.stdenv.hostPlatform.system}.default;
      consul-cni = consul-cni.packages.${prev.stdenv.hostPlatform.system}.default;
      tix = tix.packages.${prev.stdenv.hostPlatform.system}.default;
    })
  ];

  # For nixd to work properly
  nix.nixPath = ["nixpkgs=${nixpkgs}"];
}

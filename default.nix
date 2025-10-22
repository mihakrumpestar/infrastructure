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
  vars,
  hostName,
  ...
}:
#let
#customPackagesOverlay = final: _prev: let
#  args = {
#    inherit (final) stdenv lib fetchurl makeWrapper patchelf appimageTools;
#    pkgs = final;
#  };
#in
#  import ./packages args;
#in
{
  imports = [
    disko.nixosModules.disko
    nixvirt.nixosModules.default
    agenix.nixosModules.default
    stylix.nixosModules.stylix
    home-manager.nixosModules.home-manager
    {
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        backupFileExtension = "backup";
        sharedModules = [
          nixvirt.homeModules.default
          zen-browser.homeModules.beta
          agenix.homeManagerModules.default
        ];
        extraSpecialArgs = {
          inherit vars hostName;
          inherit zen-browser;
        };
      };
    }
    ./homeManagerModules
    ./hosts # Per "host"
    ./nixosModules # Per "options"
  ];

  nixpkgs.overlays = [
    nur.overlays.default
    nix-vscode-extensions.overlays.default
    #customPackagesOverlay
  ];

  # For nixd to work properly
  nix.nixPath = ["nixpkgs=${nixpkgs}"];
}

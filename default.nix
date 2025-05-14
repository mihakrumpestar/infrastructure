{
  disko,
  sops-nix,
  #agenix,
  #agenix-rekey,
  stylix,
  home-manager,
  nur,
  nix-vscode-extensions,
  nixpkgs,
  nixvirt,
  vars,
  hostName,
  ...
}: let
  customPackagesOverlay = final: _prev: let
    args = {
      inherit (final) stdenv lib fetchurl makeWrapper patchelf appimageTools;
      pkgs = final;
    };
  in
    import ./packages args;
in {
  imports = [
    disko.nixosModules.disko
    sops-nix.nixosModules.sops
    nixvirt.nixosModules.default
    #agenix.nixosModules.sops
    #agenix-rekey.nixosModules.default
    stylix.nixosModules.stylix
    home-manager.nixosModules.home-manager
    {
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        backupFileExtension = "backup";
        sharedModules = [
          sops-nix.homeManagerModules.sops
          nixvirt.homeModules.default
          #agenix.homeManagerModules.default
          #agenix-rekey.homeManagerModules.default
        ];
        extraSpecialArgs = {
          inherit vars hostName;
        };
      };
    }
    ./homeManagerModules
    ./hosts # Per "host"
    ./nixosModules # Per "options"
  ];

  nixpkgs.overlays = [
    nix-vscode-extensions.overlays.default
    nur.overlays.default
    customPackagesOverlay
  ];

  # For nixd to work properly
  nix.nixPath = ["nixpkgs=${nixpkgs}"];
}

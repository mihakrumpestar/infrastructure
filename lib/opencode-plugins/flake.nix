{
  description = "Opencode plugin pinning helpers (npm tarball -> store path, exact specs) and pin updater";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
    in
    {
      lib = import ./lib.nix;

      packages = nixpkgs.lib.genAttrs systems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        rec {
          opencode-plugins-update = pkgs.callPackage ./package.nix { };
          default = opencode-plugins-update;
        }
      );
    };
}

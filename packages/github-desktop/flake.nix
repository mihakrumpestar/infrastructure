{
  description = "GitHub Desktop with local patches";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" ];
      pkgsForSystem =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = pkgsForSystem system;
        in
        rec {
          github-desktop-local = pkgs.callPackage ./package.nix { };
          default = github-desktop-local;
        }
      );

      defaultPackage = forAllSystems (system: self.packages.${system}.default);
    };
}

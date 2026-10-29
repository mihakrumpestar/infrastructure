{
  description = "Unofficial admin CLI for the NetBird management API";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" ];
    in
    {
      packages = forAllSystems (system: {
        # Wrapped: credentials resolved from the Secret Service on invocation.
        # The stock binary is kept next to it as .netbird-manage-unwrapped.
        netbird-manage = nixpkgs.legacyPackages.${system}.callPackage ./package.nix { };
        default = self.packages.${system}.netbird-manage;
      });

      defaultPackage = forAllSystems (system: self.packages.${system}.default);
    };
}

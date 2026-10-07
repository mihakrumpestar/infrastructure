{
  description = "KeePassXC-driven OpenSSH config generator";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      packages.${system} = {
        default = pkgs.callPackage ./package.nix { };
        ssh-config-gen = self.packages.${system}.default;
      };

      defaultPackage.${system} = self.packages.${system}.default;

      homeManagerModules = {
        default = import ./hm-module.nix;
        ssh-config-gen = import ./hm-module.nix;
      };
    };
}

{
  description = "KeePassXC-driven configuration generators";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      packages.${system} = {
        default = self.packages.${system}.ssh-config-gen;
        ssh-config-gen = pkgs.callPackage ./package.nix { subPackage = "ssh-config-gen"; };
        remmina-config-gen = pkgs.callPackage ./package.nix { subPackage = "remmina-config-gen"; };
        gh-config-gen = pkgs.callPackage ./package.nix { subPackage = "gh-config-gen"; };
      };

      defaultPackage.${system} = self.packages.${system}.default;

      homeManagerModules = {
        default = import ./nix/ssh.nix;
        ssh-config-gen = import ./nix/ssh.nix;
        remmina-config-gen = import ./nix/remmina.nix;
        gh-config-gen = import ./nix/gh.nix;
      };
    };
}

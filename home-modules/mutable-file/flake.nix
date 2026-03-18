{
  description = "Home Manager module for managing mutable files";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = {...}: {
    homeModules.default = import ./module.nix;
  };
}

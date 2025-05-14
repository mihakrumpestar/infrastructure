{
  pkgs,
  fetchurl,
  ...
}: {
  zen = import ./zen.nix {inherit pkgs fetchurl;};
}

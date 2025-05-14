{
  hostName,
  lib,
  ...
}: {
  imports =
    [
      ./${hostName}/configuration.nix
      ./${hostName}/hardware-configuration.nix
    ]
    ++ lib.optionals (builtins.pathExists ./${hostName}/home.nix) [./${hostName}/home.nix];
}

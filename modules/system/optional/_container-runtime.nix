# Common container-runtime setup, applied on import by the runtime
# aspects (docker.nix, podman.nix). Underscore files are skipped by the
# den import-tree.
{ config, lib, ... }:
let
  # Native btrfs storage: docker's overlay2 and podman's overlay both fail on
  # btrfs ("no such device"). Derived from the root filesystem, not assumed,
  # so an ext4/xfs host keeps the module defaults (overlay). Set it before
  # first use: switching later orphans images.
  btrfsRoot = (config.fileSystems."/".fsType or "") == "btrfs";
in
{
  virtualisation.docker.storageDriver = lib.mkIf (
    btrfsRoot && config.virtualisation.docker.enable
  ) "btrfs";

  # storage.conf only exists once the common containers module is enabled
  # (podman enables it; docker does not).
  virtualisation.containers.storage.settings.storage.driver = lib.mkIf (
    btrfsRoot && config.virtualisation.containers.enable
  ) "btrfs";
}

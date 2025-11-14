{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.my.hardware.nvidia;

  # Nvidia Tesla P40 support
  package_ver = config.boot.kernelPackages.nvidiaPackages.mkDriver rec {
    version = "580.105.08";
    url = "https://us.download.nvidia.com/tesla/${version}/NVIDIA-Linux-x86_64-${version}.run";
    sha256_64bit = "sha256-2cboGIZy8+t03QTPpp3VhHn6HQFiyMKMjRdiV2MpNHU=";
    persistencedSha256 = "";
    fabricmanagerSha256 = "sha256-6zqB0ATeQm3umw8TMgk4KO2xlxJe9XouZQCpXfMzLQs=";
    useSettings = false;
    usePersistenced = true;
    useFabricmanager = true;
  };
in {
  options.my.hardware.nvidia = {
    enable = mkEnableOption "Nvidia datacenter GPU support";
  };

  config = mkIf cfg.enable {
    hardware = {
      graphics.enable = true;
      nvidia.datacenter.enable = true;
      nvidia.package = package_ver; # Or config.boot.kernelPackages.nvidiaPackages.dc_570;

      nvidia-container-toolkit.enable = true; # Verify: podman run --rm --device nvidia.com/gpu=all nvidia/cuda:11.0.3-base-ubuntu20.04 nvidia-smi
    };
    systemd.services.nvidia-fabricmanager.enable = lib.mkForce false;

    nixpkgs.config = {
      cudaSupport = true;
      nvidia.acceptLicense = true;
    };
  };
}

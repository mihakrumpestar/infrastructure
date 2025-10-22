{
  config,
  pkgs,
  lib,
  ...
}: {
  config = {
    boot = {
      loader = {
        systemd-boot.enable = true;
        efi.canTouchEfiVariables = true;
      };

      kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

      kernelModules =
        if config.hardware.cpu.amd.updateMicrocode
        then ["msr"] # Required for zenstates
        else [];

      # Optimizations
      kernel.sysctl = {
        # https://www.cockroachlabs.com/docs/stable/recommended-production-settings
        #"vm.swappiness" = 0; # Memory swapping required to be minimal by Cockroachdb
      };
    };

    # Optimizations
    # https://www.cockroachlabs.com/docs/stable/recommended-production-settings
    security.pam.loginLimits = [
      {
        domain = "*";
        type = "-";
        item = "nofile";
        value = "unlimited";
      } # High or unlimited no. of open files required by Cockroachdb, verify: ulimit -n
    ];
  };
}

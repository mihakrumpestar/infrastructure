{
  config,
  lib,
  ...
}: {
  config = lib.mkIf (config.my.hostType == "client") {
    services = {
      # Printing https://nixos.wiki/wiki/Printing
      printing.enable = true; # CUPS

      # Scanning and printing
      avahi = {
        # Network scanning: printing and scanning mDNS discovery won't work without it
        enable = true;
        nssmdns4 = true;
        openFirewall = true;
      };

      # Tool for monitoring, configuring and overclocking GPUs.
      lact.enable = true;
    };

    # Bluetooth
    hardware.bluetooth.enable = true;

    programs = {
      kdeconnect.enable = true;
      fuse.userAllowOther = true; # Allow (non-root) users mounting their own storage
    };

    services.virtualhere = lib.mkIf (config.my.hostSubType != "kiosk") {
      enable = true;
      enableGui = true;
    };
  };
}

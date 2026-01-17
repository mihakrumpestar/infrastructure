{
  config,
  lib,
  ...
}:
with lib; {
  services = mkIf (config.my.hostType == "client") {
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
  hardware.bluetooth.enable = config.my.hostType == "client";

  programs = mkIf (config.my.hostType == "client") {
    kdeconnect.enable = true;
    fuse.userAllowOther = true; # Allow (non-root) users mounting their own storage
  };
}

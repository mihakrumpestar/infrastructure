{
  config,
  pkgs,
  lib,
  ...
}:
#let
#brother-hll3270cdw = pkgs.callPackage ./cups-brother-hll3270cdw.nix {};
#in
with lib; {
  # Fonts
  fonts.packages = with pkgs; [
    meslo-lgs-nf # font for starship
    SDL2_ttf
    carlito
    dejavu_fonts
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-emoji
    font-awesome
    hack-font
    liberation_ttf
    roboto
    roboto-mono
    ubuntu_font_family
    fira-code
    fira-code-symbols
    mplus-outline-fonts.githubRelease
    dina-font
    proggyfonts
    xorg.fontadobe75dpi
    xorg.fontadobe100dpi
  ];

  services = mkIf (!config.my.server.enable) {
    # Printing https://nixos.wiki/wiki/Printing
    printing = {
      enable = true; # CUPS
      #logLevel = "debug"; # journalctl --follow --unit=cups
      drivers = [
        #brother-hll3270cdw
      ];
    };

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
  hardware.bluetooth.enable = !config.my.server.enable;

  programs = mkIf (!config.my.server.enable) {
    kdeconnect.enable = true;
    adb.enable = true; # Adb, fastboot
    fuse.userAllowOther = true; # Allow (non-root) users mounting their own storage
  };

  environment.systemPackages = with pkgs;
    mkIf (!config.my.server.enable) [
      kdePackages.krfb # Enables virtual-display for kdeconnect
    ];
}

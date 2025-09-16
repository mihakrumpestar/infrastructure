{
  config,
  lib,
  #pkgs,
  ...
}:
with lib; {
  options.my = {
    de.plasma = {
      enable = mkEnableOption "Custom Plasma configuration";
    };
  };

  config = mkIf config.my.de.plasma.enable {
    # Enable the Plasma desktop environment
    services = {
      # xserver.enable = true; # optional, enables Xorg
      displayManager = {
        sddm = {
          enable = true;
          wayland.enable = true;
        };
      };

      desktopManager.plasma6.enable = true;
    };

    #environment.plasma6.excludePackages = with pkgs.kdePackages; [
    #  dolphin # Memory leaks
    #];

    home-manager.sharedModules = [
      {
        home.file.".config/baloofilerc".text = ''
          [Basic Settings]
          Indexing-Enabled=false
        '';

        home.file.".config/kwalletrc".text = ''
          [Wallet]
          Enabled=false
        '';

        # Enable x11 in home-manager
        xsession.enable = true;
        xsession.windowManager.command = "…";
      }
    ];

    # DO NOT USE THIS BELOW, PLASMA WILL FAIL TO START WITH IT
    # GNOME desktop integration
    #qt = {
    #  enable = true;
    #  platformTheme = "gnome";
    #  style = "adwaita-dark";
    #};

    # Audio
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      #jack.enable = true; # Only if you need it
    };
  };
}

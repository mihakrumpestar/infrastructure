{ ... }:
{
  den.aspects.style = {
    nixos = {
      stylix = {
        enable = true;
        opacity = {
          desktop = 0.8;
          popups = 0.8;
          terminal = 0.6;
        };
        image = ./../../../assets/backgrounds/nebula-8k-wallpaper.jpg;
        polarity = "dark";

        # The gtksourceview overlay injects stylix.xml into gtksourceview{,4,5}
        # via overrideAttrs, so every dependent (inkscape, gedit, ...) diverges
        # from upstream cache.nixos.org builds and compiles from source forever.
        # GTK reads user styles from XDG data dirs, which stylix covers for
        # user sessions anyway.
        targets.gtksourceview.enable = false;
      };
    };
  };
}

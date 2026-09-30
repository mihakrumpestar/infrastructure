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

        # NOTE: targets.qt stays enabled on purpose. Stylix's qt target is the
        # only writer of qt.enable/platformTheme/style in this config; under
        # platform=kde it sets platformTheme=kde + style=breeze, which land in
        # /etc/set-environment and ~/.config/environment.d. Its eval warning
        # only means the qtct-file theming (palette/fonts/icons) is
        # unsupported for kde, not that the target is broken.
      };
    };
  };
}

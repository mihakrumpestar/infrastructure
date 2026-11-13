{ ... }:
{
  home.common = {
    homeManager =
      { ... }:
      {
        # Rofi is not installed, but stylix auto-enables its target on NixOS,
        # which still defines programs.rofi.font; home-manager renamed that to
        # programs.rofi.settings.font, so the target only emits a
        # deprecation warning. Re-enable with rofi, once stylix catches up.
        stylix.targets.rofi.enable = false;

        xdg.mimeApps = {
          enable = true;
          defaultApplications =
            let
              webBrowser = [ "librewolf.desktop" ];
            in
            {
              "default-web-browser" = webBrowser;
              "text/html" = webBrowser;
              "x-scheme-handler/http" = webBrowser;
              "x-scheme-handler/https" = webBrowser;
              "x-scheme-handler/about" = webBrowser;
              "x-scheme-handler/unknown" = webBrowser;

              "video/*" = "mpv.desktop";
            };
        };
      };
  };
}

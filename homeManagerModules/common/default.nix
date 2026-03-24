{
  xdg.mimeApps = {
    enable = true;
    defaultApplications = let
      webBrowser = ["librewolf.desktop"];
    in {
      "default-web-browser" = webBrowser;
      "text/html" = webBrowser;
      "x-scheme-handler/http" = webBrowser;
      "x-scheme-handler/https" = webBrowser;
      "x-scheme-handler/about" = webBrowser;
      "x-scheme-handler/unknown" = webBrowser;
    };
  };
}

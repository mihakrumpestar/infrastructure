{
  pkgs,
  fetchurl,
  ...
}: let
  pname = "zen";
  version = "latest";

  src = fetchurl {
    url = "https://github.com/zen-browser/desktop/releases/${version}/download/zen-x86_64.AppImage";
    sha256 = "sha256-XDamB57zU8A0k2WKo38F31sf6uTGtjIVttym+uvQBLU=";
  };

  appimageContents = pkgs.appimageTools.extract {
    inherit pname version src;
  };
in
  pkgs.appimageTools.wrapType2 {
    inherit pname version src;

    extraInstallCommands = ''
      # Install .desktop file
      install -m 444 -D ${appimageContents}/zen.desktop $out/share/applications/${pname}.desktop
      # Install icon
      install -m 444 -D ${appimageContents}/zen.png $out/share/icons/hicolor/128x128/apps/${pname}.png
    '';

    meta = {
      platforms = ["x86_64-linux"];
    };
  }

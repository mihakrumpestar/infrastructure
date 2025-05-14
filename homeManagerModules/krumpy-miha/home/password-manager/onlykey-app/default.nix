{
  config,
  lib,
  pkgs,
  ...
}: let
  onlykey-app = pkgs.buildFHSEnv {
    name = "onlykey-app";
    targetPkgs = pkgs:
      with pkgs; [
        nodejs
        glib
        nss
        nspr
        atk
        cups
        gtk3
        pango
        cairo
        gdk-pixbuf
        dbus
        xorg.libXi
        xorg.libXcursor
        xorg.libXdamage
        xorg.libXrandr
        xorg.libXcomposite
        xorg.libXext
        xorg.libXfixes
        xorg.libXrender
        xorg.libX11
        xorg.libXtst
        xorg.libXScrnSaver
        alsa-lib
        at-spi2-atk
        at-spi2-core
        libdrm
        mesa
        expat
        xorg.libxcb
        xorg.libXau
        xorg.libXdmcp
        libxkbcommon
        wayland
        libGL
        udev
        libinput
        libudev0-shim
      ];
    runScript = pkgs.writeScript "onlykey-app" ''
      #!${pkgs.bash}/bin/bash
      export LD_LIBRARY_PATH=${pkgs.libGL}/lib:${pkgs.udev}/lib:$LD_LIBRARY_PATH
      export PATH=${pkgs.udev}/bin:$PATH
      ${pkgs.nodejs}/bin/npm run --prefix ${config.home.homeDirectory}/Applications/OnlyKey-App start -- --disable-desktop-shortcuts
    '';
  };
in {
  home.packages = [
    onlykey-app
  ];

  xdg.desktopEntries = {
    onlykeyApp = {
      name = "OnlyKey-App";
      exec = "onlykey-app";
      icon = "${config.home.homeDirectory}/Applications/OnlyKey-App/resources/onlykey_logo_128.png";
      terminal = false;
      categories = ["Utility"];
      comment = "OnlyKey Application";
      # Autostart settings
      settings = {
        "X-GNOME-Autostart-enabled" = "true";
        "X-GNOME-Autostart-Delay" = "2";
        "X-KDE-autostart-after" = "panel";
        "X-LXQt-Need-Tray" = "true";
      };
    };
  };

  home.activation.installOnlyKeyApp = lib.hm.dag.entryAfter ["writeBoundary"] ''
    applications_dir="${config.home.homeDirectory}/Applications"
    mkdir -p "$applications_dir"

    app_name=OnlyKey-App
    repo_url="https://github.com/trustcrypto/OnlyKey-App.git"

    if [ ! -d "$applications_dir/$app_name" ]; then
      echo -e "\nInstalling $app_name..."

      # Clone only the latest commit of the default branch, without history
      ${pkgs.git}/bin/git clone --depth 1 --single-branch "$repo_url" "$applications_dir/$app_name"

      # Change to the application directory
      cd "$applications_dir/$app_name" || exit

      # Use nix-shell to provide an environment with Node.js and npm
      ${pkgs.nix}/bin/nix-shell -p nodejs -p nodePackages.npm --run "npm install"

      echo "Installed $app_name"
    else
      echo "$app_name is already installed."
    fi
  '';
}

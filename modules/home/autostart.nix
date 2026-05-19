{ ... }:
{
  home.autostart = {
    homeManager =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      {
        options.my.home.fullAutostart.enable = lib.mkEnableOption "Autostart apps";

        config =
          let
            autostart-minimal = pkgs.writeShellApplication {
              name = "autostart-minimal";
              text = ''
                #!/usr/bin/env bash
                echo "Starting minimal user apps"
                yakuake &
                keepassxc &
                echo "Started minimal user apps"
              '';
            };

            autostart-full = pkgs.writeShellApplication {
              name = "autostart-full";
              text = ''
                #!/usr/bin/env bash
                echo "Starting full user apps"
                bash -c "sleep 13 && codium" &
                bash -c "sleep 13 && librewolf" &
                echo "Started full user apps"
              '';
            };
          in
          lib.mkMerge [
            {
              home.packages = [
                autostart-minimal
              ];

              # Common configuration for minimal autostart
              xdg.configFile."autostart/autostart-minimal.desktop" = {
                text = ''
                  [Desktop Entry]
                  Type=Application
                  Exec=${autostart-minimal}/bin/autostart-minimal
                  Name=Start Minimal Apps
                  Icon=application-x-shellscript
                  Comment=Start my minimal applications at login
                  X-KDE-AutostartScript=true
                '';
              };
            }

            (lib.mkIf config.my.home.fullAutostart.enable {
              home.packages = [
                autostart-full
              ];

              xdg.configFile."autostart/autostart-full.desktop" = {
                text = ''
                  [Desktop Entry]
                  Type=Application
                  Exec=${autostart-full}/bin/autostart-full
                  Name=Start Apps
                  Icon=application-x-shellscript
                  Comment=Start my full applications at login
                  X-KDE-AutostartScript=true
                '';
              };
            })
          ];
      };
  };
}

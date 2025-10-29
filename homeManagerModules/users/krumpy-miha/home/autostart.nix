{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  autostart-minimal = pkgs.writeShellApplication {
    name = "autostart-minimal";
    text = ''
      #!/usr/bin/env bash

      echo "Starting minimal user apps"
      yakuake &
      keepassxc &

      bash -c "sleep 13 && nextcloud --background" &

      echo "Started minimal user apps"
    '';
  };

  autostart-full = pkgs.writeShellApplication {
    name = "autostart-full";
    text = ''
      #!/usr/bin/env bash

      echo "Starting full user apps"
      sudo -E virtualhere-client-gui --start-minimized &

      bash -c "sleep 13 && codium" &
      bash -c "sleep 13 && librewolf" &

      echo "Started full user apps"
    '';
  };
in {
  options.my = {
    home.fullAutostart.enable = mkEnableOption "Autostart apps";
  };

  config = mkMerge [
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

    (mkIf config.my.home.fullAutostart.enable {
      home.packages = [
        autostart-full
      ];

      # Conditional configuration for full autostart if `enable` is true
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
}

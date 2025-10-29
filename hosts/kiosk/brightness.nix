{pkgs, ...}: let
  brightness-server-script = pkgs.writeText "brightness-server.py" (builtins.readFile ./brightness-server.py);

  brightness-server = pkgs.writeShellApplication {
    name = "brightness-server";
    runtimeInputs = with pkgs; [
      python3
      brightnessctl
    ];
    text = ''
      python3 ${brightness-server-script} "$@"
    '';
  };
in {
  users.users.kiosk.extraGroups = ["video"];

  networking.firewall.allowedTCPPorts = [8080]; # REST server

  boot.initrd.services.udev.rules = ''
    ACTION=="add", SUBSYSTEM=="backlight", RUN+="${pkgs.coreutils}/bin/chgrp video /sys/class/backlight/%k/brightness"
    ACTION=="add", SUBSYSTEM=="backlight", RUN+="${pkgs.coreutils}/bin/chmod g+w /sys/class/backlight/%k/brightness"
    ACTION=="add", SUBSYSTEM=="leds", RUN+="${pkgs.coreutils}/bin/chgrp video /sys/class/leds/%k/brightness"
    ACTION=="add", SUBSYSTEM=="leds", RUN+="${pkgs.coreutils}/bin/chmod g+w /sys/class/leds/%k/brightness"
  '';

  # Add required packages for brightness control
  environment.systemPackages = with pkgs; [
    brightnessctl
    brightness-server
  ];

  # Add systemd user service for the brightness server
  home-manager.users.kiosk = {
    home.packages = with pkgs; [
      brightnessctl
      brightness-server
    ];

    systemd.user.services.brightness-server = {
      Unit = {
        Description = "Brightness Control REST API Server";
        After = ["graphical-session.target"];
      };

      Service = {
        Type = "simple";
        ExecStart = "${brightness-server}/bin/brightness-server";
        Restart = "on-failure";
        RestartSec = 5;
      };

      Install = {
        WantedBy = ["graphical-session.target"];
      };
    };
  };
}

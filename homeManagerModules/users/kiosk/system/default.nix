{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  username = builtins.baseNameOf (builtins.dirOf (builtins.toString ./.));
in {
  config = mkIf (builtins.elem username config.my.users) {
    users.users.${username}.extraGroups = ["video"];

    networking.firewall.allowedTCPPorts = [8080];

    boot.initrd.services.udev.rules = ''
      ACTION=="add", SUBSYSTEM=="backlight", RUN+="${pkgs.coreutils}/bin/chgrp video /sys/class/backlight/%k/brightness"
      ACTION=="add", SUBSYSTEM=="backlight", RUN+="${pkgs.coreutils}/bin/chmod g+w /sys/class/backlight/%k/brightness"
      ACTION=="add", SUBSYSTEM=="leds", RUN+="${pkgs.coreutils}/bin/chgrp video /sys/class/leds/%k/brightness"
      ACTION=="add", SUBSYSTEM=="leds", RUN+="${pkgs.coreutils}/bin/chmod g+w /sys/class/leds/%k/brightness"
    '';

    environment.systemPackages = with pkgs; [
      brightnessctl
    ];

    services.displayManager = {
      autoLogin = {
        enable = true;
        user = username;
      };
    };
  };
}

{ den, inputs, ... }:
let
  data = import "${inputs.infrastructure-secrets}/secrets/users/root/data.nix";
in
{
  den.aspects.kiosk-user = {
    includes = [
      den.aspects.hm-common
      den.aspects.kiosk-browser
      den.aspects.kiosk-brightness
    ];
    nixos =
      {
        pkgs,
        ...
      }:
      {
        users.users."kiosk" = {
          uid = 1002;
          group = "users";
          openssh.authorizedKeys.keys = [
            data.ssh_authorized_keys.client
          ];
          extraGroups = [
            "video"
            "networkmanager"
          ];
        };

        networking.firewall.allowedTCPPorts = [ 8080 ];

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
            user = "kiosk";
          };
        };
      };
  };
}

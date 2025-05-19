{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  config = mkIf config.my.client.enable {
    hardware.onlykey.enable = true;

    services.virtualhere.enable = true;

    # Docs: https://wiki.nixos.org/wiki/Yubikey
    security.pam = {
      u2f = {
        enable = true;
        # control = "required"; # then you have to enter password too (strange logic but ok)
        settings = {
          authfile = config.sops.secrets.pam_u2f.path; # Generate using: pamu2fcfg -u username -o pam://hostname
          interactive = true; # Needed so that it does not wait for device if it is not present on KDE screensaver // TODO: maybe modify /etc/login.defs LOGIN_TIMEOUT
          cue = true;
        };
      };
      # All services have u2fAuth enabled if it is enabled globaly with security.pam.u2f.enable
      services = {
        "sshd".u2fAuth = false;
        "login".allowNullPassword = mkForce false; # security.shadow.enable sets this to true
        "login".unixAuth = false;
        "sudo".unixAuth = false; # Prevent password prompts
        "kde".unixAuth = false; # KDE scrensaver
        "kde".allowNullPassword = mkForce false;
      };
    };

    sops = {
      secrets.pam_u2f.mode = "0444"; # KDE screensaver does not have root rights to access the config
    };

    # Test pam:
    # nix-shell -p pamtester
    # pamtester login <username> authenticate
    # pamtester sudo <username> authenticate

    # SSH agent
    programs.ssh = {
      startAgent = true;
      enableAskPassword = true;
      askPassword = "${pkgs.kdePackages.ksshaskpass}/bin/ksshaskpass";
    };
  };
}

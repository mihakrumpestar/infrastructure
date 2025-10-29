{
  config,
  pkgs,
  lib,
  username,
  ...
}:
with lib; let
  store-secrets = config.home-manager.user.${username}.my.store-secrets.secrets;
in {
  users.users.${username}.extraGroups = [
    "docker"
    "libvirtd"
    "kvm"
    "virtualhere"
    "adbusers"
    "wheel"
    "tss"
    "plugdev" # Old onlykey
  ];

  # OnlyKey
  users.groups.plugdev = {};

  # /etc/hosts
  networking.extraHosts = store-secrets."krumpy-miha_hosts";

  # Security
  hardware.onlykey.enable = true;

  my.services.virtualhere.enable = true;

  # Docs: https://wiki.nixos.org/wiki/Yubikey
  security.pam = {
    u2f = {
      enable = true;
      # control = "required"; # then you have to enter password too (strange logic but ok)
      settings = {
        authfile = pkgs.writeText "pam_u2f" store-secrets.pam_u2f; # Generate using: pamu2fcfg -u username -o pam://hostname
        # If using SOPS or AGENIX use file: mode = "0444"; # KDE screensaver does not have root rights to access the config
        interactive = true; # Needed so that it does not wait for device if it is not present on KDE screensaver // TODO: maybe modify /etc/login.defs LOGIN_TIMEOUT
        cue = true;
      };
    };

    # All services have u2fAuth enabled if it is enabled globaly with security.pam.u2f.enable, so we sill disable regular passwords here
    services = {
      "sshd".u2fAuth = false;
      "login".allowNullPassword = mkForce false; # security.shadow.enable sets this to true
      "login".unixAuth = false;
      "sudo".unixAuth = false; # Prevent password prompts
      "kde".unixAuth = false; # KDE scrensaver
      "kde".allowNullPassword = mkForce false;
    };
  };

  # Test pam:
  # nix-shell -p pamtester
  # pamtester login <username> authenticate
  # pamtester sudo <username> authenticate

  networking.firewall.allowedTCPPorts = [
    8080 # For development
  ];
}

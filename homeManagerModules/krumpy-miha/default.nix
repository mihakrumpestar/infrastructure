{
  config,
  lib,
  ...
}:
with lib; let
  username = "krumpy-miha";
in {
  options.my = {
    users.${username}.enable = mkEnableOption "Enable this user";
  };

  imports = [
    (import ./config {inherit config lib username;})
  ];

  config = mkIf config.my.users.${username}.enable {
    users.users.${username} = {
      isNormalUser = true;
      linger = true; # Make sure user services are started on boot
      # initialHashedPassword = "something"; # Generate using: mkpasswd
      # Remove password: passwd -d username
      extraGroups = [
        "networkmanager"
        "docker"
        "libvirtd"
        "kvm"
        "virtualhere"
        "adbusers"
        "wheel"
        "tss"
        "plugdev" # Old onlykey
      ];
    };

    # OnlyKey
    users.groups.plugdev = {};

    home-manager.users.${username} = import ./home;
  };
}

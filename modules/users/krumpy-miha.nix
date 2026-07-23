{ home, inputs, ... }:
let
  data = import "${inputs.infrastructure-secrets}/secrets/users/root/data.nix";
  userData = import "${inputs.infrastructure-secrets}/secrets/users/krumpy-miha/data.nix";
in
{
  den.aspects.krumpy-miha = {
    includes = [
      home.common
      home.ssh
      home.git
      home.web-browser
      home.storage
      home.home-apps
      home.ide
      home.llm
      home.password-manager
      home.clipboard
      home.autostart
      home.scripts
    ];

    homeManager = _: {
      my.ssh.hosts = userData.ssh.hosts;
      my.git.identities = userData.git.identities;
    };
    nixos =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      {
        users.users."krumpy-miha" = {
          isNormalUser = true;
          linger = true; # Make sure user services are started on boot
          uid = 1000;
          group = "users";
          openssh.authorizedKeys.keys = [
            data.ssh_authorized_keys.client # Allow administrator to login as any user
          ];
          extraGroups = [
            "docker"
            "libvirtd"
            "kvm"
            "virtualhere"
            "adbusers"
            "wheel"
            "tss"
            "plugdev" # Old onlykey
            "networkmanager"
          ];
        };

        # OnlyKey
        users.groups.plugdev = { };
        hardware.onlykey.enable = true;
        # https://github.com/trustcrypto/python-onlykey/issues/82#issuecomment-3503421686
        nixpkgs.config.permittedInsecurePackages = [
          "python3.14-ecdsa-0.19.2"
        ];

        age.secrets."pam_u2f" = {
          file = "${inputs.infrastructure-secrets}/secrets/users/krumpy-miha/pam_u2f.age";
          mode = "0444"; # KDE screensaver does not have root rights to access the config
        };

        # Docs: https://wiki.nixos.org/wiki/Yubikey
        security.pam = {
          u2f = {
            enable = true;
            # control = "required"; # then you have to enter password too (strange logic but ok)
            settings = {
              authfile = config.age.secrets."pam_u2f".path; # Generate using: pamu2fcfg -u username -o pam://hostname
              interactive = true; # Needed so that it does not wait for device if it is not present on KDE screensaver // TODO: maybe modify /etc/login.defs LOGIN_TIMEOUT
              cue = true;
            };
          };
          services = {
            "sshd".u2fAuth = false;
            "login".allowNullPassword = lib.mkForce false; # security.shadow.enable sets this to true
            "login".unixAuth = false;
            "sudo".unixAuth = false; # Prevent password prompts
            "kde".unixAuth = false; # KDE screensaver
            "kde".allowNullPassword = lib.mkForce false;
          };
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

        # USB device sharing
        services.virtualhere = {
          enable = true;
          enableGui = true;
        };
      };
  };
}

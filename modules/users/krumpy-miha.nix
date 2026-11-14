{
  home,
  inputs,
  ...
}:
let
  data = import "${inputs.infrastructure-secrets}/secrets/users/root/data.nix";
  keepassDatabase = "~/Documents/digital-identity/KeePass.kdbx";
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
      home.note-taking
      home.ide
      home.llm
      home.password-manager
      home.clipboard
      home.autostart
      home.scripts
    ];

    homeManager = _: {
      programs.ssh-config-gen = {
        enable = true;
        database = keepassDatabase;
        yubikey = "1";
        noPassword = true;
        git.enable = true;
      };

      programs.remmina-config-gen = {
        enable = true;
        database = keepassDatabase;
        yubikey = "1";
        noPassword = true;
      };

      # gh reads account metadata from ~/.config/gh/hosts.yml and the token from
      # the Secret Service. KeePassXC publishes both, so accounts follow the
      # database across machines instead of being re-authenticated per host.
      programs.gh-config-gen.enable = true;
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
            "podman"
            "libvirtd"
            "kvm"
            "virtualhere"
            "adbusers"
            "wheel"
            "lpadmin" # CUPS admin: manage printers/queues without sudo
            "tss"
            "plugdev" # Old onlykey
            "networkmanager"
            "netbird" # NetBird control socket access (services.netbird in networking.nix)
          ];
        };

        # OnlyKey
        users.groups.plugdev = { };
        hardware.onlykey.enable = true;
        # https://github.com/trustcrypto/python-onlykey/issues/82#issuecomment-3503421686
        nixpkgs.config.permittedInsecurePackages = [
          "python3.14-ecdsa-0.19.2"
          # onlykey (nwjs-based wrapper) pulls nwjs, marked insecure for bundled Chrome vulnerabilities
          "nwjs-0.102.1"
        ];

        age.secrets."pam_u2f" = {
          file = "${inputs.infrastructure-secrets}/secrets/users/krumpy-miha/pam_u2f.age";
          # kscreenlocker's PAM worker runs as the logged-in user (no setuid anywhere in that
          # path), and pam_u2f opens the authfile with its own euid. Keep it world-readable:
          # restricting it to a group couples the lock screen to group membership, and a
          # mismatch is a silent lockout because pam_u2f is `sufficient` and pam_deny is the
          # only other auth line. The file holds key handles and public keys, not secrets.
          mode = "0444";
        };

        # FIDO2 PIN (keyboard, not the OnlyKey keypad PIN), needed by pamu2fcfg and every login:
        #   onlykey-cli set-pin     # or change-pin
        #
        # The authfile is bound to one relying party (rpId), so it must be generated with the
        # same value as `origin` below, or every assertion fails and login is denied:
        #   F=secrets/users/krumpy-miha/pam_u2f
        #   pamu2fcfg -o pam://nixos -i pam://nixos -u krumpy-miha --pin-verification > "$F"
        #
        # Second key later: same command with -n, appended to the same file (one tap each),
        # because a repeated username on its own line replaces the earlier one.
        #   pamu2fcfg -o pam://nixos -i pam://nixos -u krumpy-miha --pin-verification -n >> "$F"
        #
        # Docs: https://wiki.nixos.org/wiki/Yubikey
        security.pam = {
          u2f = {
            enable = true;
            settings = {
              authfile = config.age.secrets."pam_u2f".path;
              cue = true;
              pinverification = 1;
              # The authfile's credentials are bound to one rpId. Without this, pam_u2f uses
              # "pam://$HOSTNAME" and every assertion fails with FIDO_ERR_NO_CREDENTIALS.
              # Must equal `pamu2fcfg -o`. appid is legacy (old-format credentials only) and
              # defaults to origin.
              origin = "pam://nixos";
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

        # Bounds the whole login(1) PAM conversation incl. the u2f wait: shadow's login arms
        # alarm(LOGIN_TIMEOUT) at startup and only cancels it after successful auth.
        # Affects only the "login" service, not sudo or the KDE screensaver. Default is 60.
        security.loginDefs.settings.LOGIN_TIMEOUT = 30;

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

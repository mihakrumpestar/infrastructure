{
  home,
  inputs,
  ...
}:
let
  data = (import "${inputs.infrastructure-secrets}/secrets/data.nix").root;
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
      home.task-app
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
            "disk"
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

        sops.secrets."pam_u2f" = {
          sopsFile = "${inputs.infrastructure-secrets}/secrets/sops/krumpy-miha.yaml";
          key = "krumpy-miha/pam_u2f";
          # kscreenlocker's PAM worker runs as the logged-in user (no setuid in that path) and
          # pam_u2f opens the authfile with its own euid, so uid 1000 needs read access; it gets
          # it through its primary group. Root keeps ownership: an authfile owned by that uid is
          # writable by every one of its processes, and pam_u2f is `sufficient` for login, sudo
          # and kde, so a user-writable authfile is a passwordless sudo. Group must resolve on
          # every host or the screen lock silently stops accepting the key.
          mode = "0440";
          group = "users";
        };

        # FIDO2 PIN (keyboard, not the OnlyKey keypad PIN), needed by pamu2fcfg and every login:
        #   onlykey-cli set-pin     # or change-pin
        #
        # The authfile is bound to one relying party (rpId), so it must be generated with the
        # same value as `origin` below, or every assertion fails and login is denied.
        # The value lives in sops, so generate it in a temp file and put it back:
        #   cd secrets
        #   F=$(mktemp)
        #   task get -- '["krumpy-miha"]["pam_u2f"]' secrets/sops/krumpy-miha.yaml > "$F"
        #   pamu2fcfg -o pam://nixos -i pam://nixos -u krumpy-miha --pin-verification > "$F"
        #   task edit -- secrets/sops/krumpy-miha.yaml   # replace the pam_u2f block with the file contents
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
              authfile = config.sops.secrets."pam_u2f".path;
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
            # Wait for Enter before touching the key. Otherwise the lock screen opens the
            # key on its own, blocking SDDM and sudo, and retries in a loop when it is
            # absent. Only the lock screen gets this extra step.
            "kde".rules.auth.u2f.settings.interactive = lib.mkForce true;
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

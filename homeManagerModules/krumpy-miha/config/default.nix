{
  config,
  lib,
  vars,
  ...
}:
with lib; {
  config = mkIf config.my.users.krumpy-miha.enable {
    # /etc/hosts
    networking.extraHosts = config.my.store-secrets.secrets."krumpy-miha_hosts";

    # Security
    hardware.onlykey.enable = true;

    my.services.virtualhere.enable = true;

    # Docs: https://wiki.nixos.org/wiki/Yubikey
    security.pam = {
      u2f = {
        enable = true;
        # control = "required"; # then you have to enter password too (strange logic but ok)
        settings = {
          authfile = config.age.secrets.pam_u2f.path; # Generate using: pamu2fcfg -u username -o pam://hostname
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

    age.secrets.pam_u2f = {
      file = /${vars.secretsDir}/secrets/users/krumpy-miha/pam_u2f.age;
      mode = "0444"; # KDE screensaver does not have root rights to access the config
    };

    # Test pam:
    # nix-shell -p pamtester
    # pamtester login <username> authenticate
    # pamtester sudo <username> authenticate

    networking.firewall.allowedTCPPorts = [
      8080 # For development
    ];

    # Email

    # Policies are global only, that is why they are here and not in home-manager
    programs.thunderbird = {
      enable = true;
      # package = pkgs.betterbird; # Was removed from nixpkgs :(
      policies = {
        BackgroundAppUpdate = false;
        DisableAppUpdate = true;
        DisableMasterPasswordCreation = true;
        DisablePasswordReveal = true;
        DisableSecurityBypass = true;
        DisableSystemAddonUpdate = true;
        DisableTelemetry = true;
        ExtensionUpdate = true;

        HardwareAcceleration = true;

        NetworkPrediction = false;
        OfferToSaveLogins = false;
        OfferToSaveLoginsDefault = false;
        PasswordManagerEnabled = false;
        PrimaryPassword = false;
        PromptForDownloadLocation = true;

        ExtensionSettings = let
          extensions = {
            # Get ID using go to addons -> Settings icons -> Debug Addons
            "grammar-and-spell-checker" = "languagetool-mailextension@languagetool.org";
            "attachment-image-viewer" = "imageview@opto.one";
            "check-and-send" = "{1B0ADFEC-846C-401D-BA54-7842CBD485D4}";
            "copy-address" = "copyaddrs@pqpq.dev";
            "darkreader" = "addon@darkreader.org";
            "display-mail-user-agent-t" = "DisplayMailUserAgent-T@Toshi_";
            "dkim-verifier" = "dkim_verifier@pl";
            "web_translate" = "admin@fastaddons.com_WebTranslate";
            "emojiaddin" = "emoji@ganss.org";
            "importexporttools-ng" = "ImportExportToolsNG@cleidigh.kokkini.net";
            "printingtools-ng" = "PrintingToolsNG@cleidigh.kokkini.net";
            "keepassxc-mail" = "keepassxc-mail@kkapsner.de";
            #"minimize-on-close" = "minimizeonclose@rsjtdrjgfuzkfg.com";
            "replyasoriginalrecipientup" = "ReplyAsOriginalRecipient@github.com";
            "threadvis" = "{A23E4120-431F-4753-AE53-5D028C42CFDC}";
            "send-later-3" = "sendlater3@kamens.us";
            "quicktext" = "{8845E3B3-E8FB-40E2-95E9-EC40294818C4}";
            "shrunked_image_resizer" = "shrunked@darktrojan.net";
            "dark-black-theme" = "DuctTape-Dark@addons.thunderbird.net"; # Theme
          };
          mappedExtensions =
            lib.mapAttrs' (
              name: id:
                lib.nameValuePair id {
                  install_url = "https://addons.thunderbird.net/thunderbird/downloads/latest/${name}/latest.xpi";
                  installation_mode = "normal_installed"; # Allow disabling, auto-install
                }
            )
            extensions;
        in
          {
            "*" = {
              installation_mode = "blocked";
              blocked_install_message = "Manual extension installation is forbidden!";
            };
          }
          // mappedExtensions;
      };
    };
  };
}

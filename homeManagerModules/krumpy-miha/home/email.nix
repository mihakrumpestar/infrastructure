{
  config,
  pkgs,
  ...
}: {
  accounts.email.accounts = {
    main = let
      inherit (config.my.store-secrets.secrets.email) host;
      inherit (config.my.store-secrets.secrets.email) realName;
      inherit (config.my.store-secrets.secrets.email) address;
    in {
      smtp = {
        inherit host;
        port = 465;
        tls.enable = true;
      };
      imap = {
        inherit host;
        port = 993;
        tls.enable = true;
      };
      inherit address;
      primary = true;
      inherit realName;
      userName = address;
      # passwordCommand = ""; # programs.thunderbird does not use this
      thunderbird = {
        enable = true;
      };
    };
  };

  programs.thunderbird = {
    enable = true;
    # package = pkgs.betterbird; # Was removed from nixpkgs :(
    profiles = {
      main = {
        isDefault = true;
        settings = {
          "browser.theme.content-theme" = 0;
          "browser.theme.toolbar-theme" = 0;
          "extensions.activeThemeID" = "DuctTape-Dark@addons.thunderbird.net";
          "mail.minimizeToTray" = true;
          "mail.pane_config.dynamic" = 2;
          "mail.shell.checkDefaultClient" = false;
          "mailnews.start_page.enabled" = false;
          "messenger.options.messagesStyle.variant" = "Dark";
          "pref.general.disable_button.default_mail" = false;
          "mailnews.attachments.display.top" = true;
          "mailnews.quotingPrefs.version" = 1; # Start my reply above the quote
        };
      };
    };
  };

  home.file.".mozilla/native-messaging-hosts/de.kkapsner.keepassxc_mail.json".text = builtins.toJSON {
    allowed_extensions = ["keepassxc-mail@kkapsner.de"];
    description = "KeePassXC integration with native messaging support";
    name = "de.kkapsner.keepassxc_mail";
    path = "${pkgs.keepassxc}/bin/keepassxc-proxy";
    type = "stdio";
  };
}

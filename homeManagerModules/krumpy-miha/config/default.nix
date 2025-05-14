{
  config,
  lib,
  username,
  ...
}:
with lib; {
  config = mkIf config.my.users.${username}.enable {
    # Policies are global only
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

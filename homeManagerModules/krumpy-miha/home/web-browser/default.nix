{
  config,
  lib,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    brave
    chromium
    ladybird
    floorp
    responsively-app # For responsive web dev

    zen # Custom
  ];

  # Docs:
  # https://github.com/NiXium-org/NiXium/blob/central/src/nixos/users/kira/home/modules/web-browsers/firefox/firefox.nix

  # TODO: https://discourse.nixos.org/t/automatic-firejail-of-home-managers-librewolf-does-not-work/22291

  stylix.targets.librewolf.profileNames = ["default"];

  programs.librewolf = {
    enable = true;
    profiles = {
      default = {
        id = 0;
        isDefault = true;
        settings = {
          # Extend
          "extensions.autoDisableScopes" = 0; # Enable profile extensions
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true; # enable userChrome and userContent

          # UI modifications
          "browser.aboutConfig.showWarning" = false; # disable about:config warning
          "browser.display.use_document_fonts" = 0; # Disable "Allow pages to choose their own fonts, instead of your selections above" as those fonts are pixelated
          "reader.parse-on-load.enabled" = false; # Disable "Reader view"

          "ui.systemUsesDarkTheme" = 1; # Dark theme prefered
          "layout.css.prefers-color-scheme.content-override" = 0; # Force dark mode

          "browser.startup.page" = 3; # set startup page: 0=blank, 1=home, 2=last visited page, 3=resume previous session

          "findbar.modalHighlight" = true;
          "findbar.highlightAll" = true;
          "browser.toolbars.bookmarks.visibility" = "never";

          "browser.urlbar.shortcuts.bookmarks" = false;
          "browser.proton.toolbar.version" = 3; # Enable toolbar
          "browser.theme.toolbar-theme" = 0; # Same as above

          "dom.events.asyncClipboard.clipboardItem" = true;

          "network.protocol-handler.external.mailto" = false; # Remove annoying "add application for mailto links"

          # Privacy
          "privacy.resistFingerprinting" = true; # Instead of using CanvasBlocker extension
          "privacy.resistFingerprinting.pbmode" = true;
          "privacy.resistFingerprinting.autoDeclineNoUserInputCanvasPrompts" = true;
          "privacy.donottrackheader.enabled" = true;

          "general.useragent.override" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:134.0) Gecko/20100101 Firefox/134.0"; # Does not work when resistFingerprinting is enabled

          # Overrides of arkenfox-js

          # override recipe: enable session restore
          "privacy.sanitize.sanitizeOnShutdown" = false;
          "browser.sessionstore.privacy_level" = 0; # 1003 optional to restore cookies/formdata
          "privacy.clearOnShutdown_v2.historyFormDataAndDownloads" = false; # 2811 FF128+

          # override recipe: keep cookies restart
          "privacy.clearOnShutdown_v2.cookiesAndStorage" = false; # Cookies, Site Data, Active Logins [FF128+]
        };
        #extraConfig = builtins.readFile "${pkgs.arkenfox-userjs}/user.js"; # TODO: this currently overrides our settings above as it applies it later
        userChrome = builtins.readFile ./userChrome.css;
        #extensions = with config.nur.repos.rycee.firefox-addons; [ ];
        search = {
          force = true;
          engines = {
            "Nix Packages" = {
              id = "nix_packages";
              urls = [
                {
                  template = "https://search.nixos.org/packages";
                  params = [
                    {
                      name = "channel";
                      value = "unstable";
                    }
                    {
                      name = "type";
                      value = "packages";
                    }
                    {
                      name = "query";
                      value = "{searchTerms}";
                    }
                  ];
                }
              ];
              definedAliases = ["@np"];
              icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
            };

            "Nix Options" = {
              id = "nix_options";
              urls = [
                {
                  template = "https://search.nixos.org/options";
                  params = [
                    {
                      name = "channel";
                      value = "unstable";
                    }
                    {
                      name = "type";
                      value = "packages";
                    }
                    {
                      name = "query";
                      value = "{searchTerms}";
                    }
                  ];
                }
              ];
              definedAliases = ["@no"];
              icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
            };

            "Home Manager Options" = {
              id = "hm_options";
              urls = [
                {
                  template = "https://home-manager-options.extranix.com/";
                  params = [
                    {
                      name = "query";
                      value = "{searchTerms}";
                    }
                  ];
                }
              ];
              definedAliases = ["@hm"];
              icon = "https://icons.duckduckgo.com/ip3/home-manager-options.extranix.com.ico";
            };

            "NixOS Wiki" = {
              id = "nixos_wiki";
              urls = [{template = "https://wiki.nixos.org/index.php?search={searchTerms}";}];
              updateInterval = 24 * 60 * 60 * 1000; # every day
              definedAliases = ["@nw"];
              icon = "https://wiki.nixos.org/favicon.png";
            };

            "ddg" = {
              id = "ddg";
              urls = [{template = "https://duckduckgo.com";}];
              params = [
                {
                  name = "q";
                  value = "{searchTerms}";
                }
              ];
              definedAliases = ["@d"];
              icon = "https://icons.duckduckgo.com/ip3/duckduckgo.com.ico";
            };

            "Brave" = {
              id = "brave";
              urls = [{template = "https://search.brave.com/search";}];
              params = [
                {
                  name = "q";
                  value = "{searchTerms}";
                }
              ];
              definedAliases = ["@b"];
              icon = "https://icons.duckduckgo.com/ip3/search.brave.com.ico";
            };

            "SearXNG" = let
              inherit (config.my.store-secrets.secrets) searxng;
            in {
              id = "searxng";
              urls = [{template = "${searxng}/search?q={searchTerms}";}];
              params = [
                {
                  name = "q";
                  value = "{searchTerms}";
                }
              ];
              definedAliases = ["@searxng"];
              icon = "${searxng}/favicon.ico";
            };

            "bing" = {
              id = "bing";
              metaData.hidden = true;
            };

            "google" = {
              id = "google";
              metaData.hidden = true;
            };
          };

          order = [
            "SearXNG"
            "ddg"
            "Brave"
            "Nix Packages"
            "Nix Options"
            "Home Manager Options"
            "NixOS Wiki"
          ];

          default = "SearXNG";
          privateDefault = "ddg";
        };
      };
    };

    #nativeMessagingHosts = with pkgs; [ # Use this after it is fixed (currently always maps to Firefox and not Librewolf)
    #  keepassxc # keepassxc does this by itself for Firefox
    #];

    # Docs: https://mozilla.github.io/policy-templates/#extensionsettings
    # Inspiration: https://github.com/NiXium-org/NiXium/blob/central/src/nixos/users/kira/home/modules/web-browsers/firefox/firefox.nix
    policies = {
      AppAutoUpdate = false; # Disable automatic application update
      BackgroundAppUpdate = false; # Disable automatic application update in the background, when the application is not running.
      DisableFirefoxStudies = true;
      DisableFirefoxAccounts = true; # Disable Firefox Sync
      DisableFirefoxScreenshots = true; # No screenshots?
      DisableForgetButton = true; # Thing that can wipe history for X time, handled differently
      DisableMasterPasswordCreation = true; # To be determined how to handle master password
      DisableProfileImport = true; # Purity enforcement: Only allow nix-defined profiles
      DisableProfileRefresh = true; # Disable the Refresh Firefox button on about:support and support.mozilla.org
      DisableSetDesktopBackground = true; # Remove the “Set As Desktop Background…” menuitem when right clicking on an image, because Nix is the only thing that can manage the backgroud
      DisplayMenuBar = "default-off";
      DisablePocket = true;
      DisableTelemetry = true;
      DisableFormHistory = true;
      DisablePasswordReveal = true;
      DontCheckDefaultBrowser = true; # Stop asking for attention
      #HardwareAcceleration = false; # Disabled as it's exposes points for fingerprinting # DO NOT USE as it makes all sites slow
      OfferToSaveLogins = false; # Managed by KeePassXC instead
      EnableTrackingProtection = {
        Value = true;
        Locked = true;
        Cryptomining = true;
        Fingerprinting = true;
        EmailTracking = true;
        # Exceptions = ["https://example.com"]
      };
      EncryptedMediaExtensions = {
        Enabled = true;
        Locked = true;
      };
      ExtensionUpdate = false;

      ExtensionSettings = let
        extensions = {
          # Get ID using about:debugging#/runtime/this-firefox
          # "name" = "ID";
          "ublock-origin" = "uBlock0@raymondhill.net";
          "darkreader" = "addon@darkreader.org";
          "gitowl" = "gitowl@gitowl.dev";
          "imagus" = "{00000f2a-7cde-4f20-83ed-434fcb420d71}";
          "medium-parser" = "medium-parser@example.com";
          "tabliss" = "extension@tabliss.io";
          "traduzir-paginas-web" = "{036a55b4-5e72-4d05-a06c-cba2dfcc134a}";
          "nicothin-space" = "{22b0eca1-8c02-4c0d-a5d7-6604ddd9836e}";
          "aw-watcher-web" = "{ef87d84c-2127-493f-b952-5b4e744245bc}";
          "languagetool" = "languagetool-webextension@languagetool.org";
          "keepassxc-browser" = "keepassxc-browser@keepassxc.org";
          "scroll_anywhere" = "juraj.masiar@gmail.com_ScrollAnywhere";
          "sidebery" = "{3c078156-979c-498b-8990-85f7987dd929}";
          "cookie-autodelete" = "CookieAutoDelete@kennydo.com";
          #"javascript-restrictor" = "jsr@javascriptrestrictor"; # JShelter
          "refined-github-" = "{a4c4eda4-fb84-4a84-b4a1-f7c1cbf2a1ad}";
          #"noscript" = "{73a6fe31-595d-460b-a920-fcc0f8843232}";
          "karakeep" = "addon@karakeep.app";
          "unpaywall" = "{f209234a-76f0-4735-9920-eb62507a54cd}";
          "enhancer-for-youtube" = "enhancerforyoutube@maximerf.addons.mozilla.org";
        };
        mappedExtensions =
          lib.mapAttrs' (
            name: id:
              lib.nameValuePair id {
                install_url = "https://addons.mozilla.org/firefox/downloads/latest/${name}/latest.xpi";
                installation_mode = "normal_installed"; # Allow disabling, auto-install
                default_area = "navbar"; # Pinned (only applies on first start)
              }
          )
          extensions;
      in
        #{ # This blocks about:debugging page
        #  "*" = {
        #    installation_mode = "blocked";
        #    blocked_install_message = "Manual extension installation is forbidden!";
        #  };
        #}
        {
          # Manual sources
        }
        // mappedExtensions;

      "3rdparty".Extensions = {
        "uBlock0@raymondhill.net".adminSettings = lib.importJSON ./ublock-origin.json;
        "juraj.masiar@gmail.com_ScrollAnywhere" = lib.importJSON ./scroll_anywhere.json;
        "keepassxc-browser@keepassxc.org".settings = lib.importJSON ./keepassxc-browser.json;
        # aw-watcher-web
        "{ef87d84c-2127-493f-b952-5b4e744245bc}" = {
          "consentOfflineDataCollection" = true;
        };
        /*
        "languagetool-webextension@languagetool.org".properties = { # TODO: does not work
          apiServerUrl = "https://test.com/v2";
          hasPickyModeEnabledGlobally = true;
          hasRephrasingEnabled = true;
          hasSeenOnboarding = true;
          hasSeenPrivacyConfirmationDialog = true;
          hasSynonymsEnabled = true;
          isNewUser = false;
          preferredLanguages = [ "en" "sl" ];
        };
        */
      };

      FirefoxHome = {
        Search = true;
        TopSites = true;
        SponsoredTopSites = false;
        Highlights = true;
        Pocket = false;
        SponsoredPocket = false;
        Snippets = false;
        Locked = true;
      };
      FirefoxSuggest = {
        WebSuggestions = false;
        SponsoredSuggestions = false;
        ImproveSuggest = false;
        Locked = true;
      };
      NoDefaultBookmarks = true;
      PasswordManagerEnabled = false; # Managed by KeePassXC
      #PDFjs = {
      #  Enabled = false; # Do not disable uild in in PDFs
      #  EnablePermissions = false;
      #};
      PictureInPicture = {
        Enabled = true;
        Locked = true;
      };
      PromptForDownloadLocation = true;
      /*
      Proxy = {
        Mode = "system"; # none | system | manual | autoDetect | autoConfig;
        Locked = true;
        # HTTPProxy = hostname;
        # UseHTTPProxyForAllProtocols = true;
        # SSLProxy = hostname;
        # FTPProxy = hostname;
        SOCKSProxy = "127.0.0.1:9050"; # Tor
        SOCKSVersion = 5; # 4 | 5
        #Passthrough = <local>;
        # AutoConfigURL = URL_TO_AUTOCONFIG;
        # AutoLogin = true;
        UseProxyForDNS = true;
      };
      SanitizeOnShutdown = {
        Cache = true;
        Cookies = false;
        Downloads = true;
        FormData = true;
        History = false;
        Sessions = false;
        SiteSettings = false;
        OfflineApps = true;
        Locked = true;
      };
      */
      SearchEngines = {
        # This does not apply for some reason, use per profile settings as those work
      };
      SearchSuggestEnabled = false;
      ShowHomeButton = false;
      StartDownloadsInTempDirectory = true;
      UserMessaging = {
        ExtensionRecommendations = false; # Don’t recommend extensions while the user is visiting web pages
        FeatureRecommendations = false; # Don’t recommend browser features
        Locked = true; # Prevent the user from changing user messaging preferences
        MoreFromMozilla = false; # Don’t show the “More from Mozilla” section in Preferences
        SkipOnboarding = true; # Don’t show onboarding messages on the new tab page
        UrlbarInterventions = false; # Don’t offer suggestions in the URL bar
        WhatsNew = false; # Remove the “What’s New” icon and menuitem
      };
      UseSystemPrintDialog = true;
    };
  };

  # Use this until Librewolf path is not fixed
  home.file.".librewolf/native-messaging-hosts/org.keepassxc.keepassxc_browser.json".text = ''
    {
        "name": "org.keepassxc.keepassxc_browser",
        "description": "KeePassXC integration with native messaging support",
        "path": "${pkgs.keepassxc}/bin/keepassxc-proxy",
        "type": "stdio",
        "allowed_extensions": [
            "keepassxc-browser@keepassxc.org"
        ]
    }
  '';
}

{
  config,
  pkgs,
  zen-browser,
  lib,
  ...
}: let
  store-secrets = config.my.store-secrets.secrets;
in {
  home.packages = with pkgs; [
    keepassxc
  ];

  stylix.targets.zen-browser.profileNames = ["default"];

  programs.zen-browser = {
    suppressXdgMigrationWarning = true;
    enable = true;
    nativeMessagingHosts = with pkgs; [
      keepassxc
    ];
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
      ExtensionUpdate = true;

      ExtensionSettings = let
        extensions = {
          # Get ID using about:debugging#/runtime/this-firefox
          # "name" = "ID";
          "ublock-origin" = "uBlock0@raymondhill.net";
          "darkreader" = "addon@darkreader.org";
          "medium-parser" = "medium-parser@example.com";
          "tabliss" = "extension@tabliss.io";
          "nicothin-space" = "{22b0eca1-8c02-4c0d-a5d7-6604ddd9836e}";
          "keepassxc-browser" = "keepassxc-browser@keepassxc.org";
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
    };
    profiles = {
      default = {
        id = 0;
        isDefault = true;
        settings = {
          # Homepage configuration
          "browser.startup.homepage" = store-secrets.dashboard;
          "browser.startup.page" = 1; # Always start with homepage

          # Configure home button behavior
          "browser.startup.homepage_override.mstone" = "ignore";
          "browser.toolbarbuttons.introduced.pocket-button" = false;

          # Session and navigation
          "browser.uidensity" = 1; # Compact mode

          # Hide bookmarks and keep interface clean
          "browser.toolbars.bookmarks.visibility" = "never";
          "places.history.enabled" = false;

          # Mine

          # Extend
          "extensions.autoDisableScopes" = 0; # Enable profile extensions
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true; # enable userChrome and userContent

          # UI modifications
          "browser.aboutConfig.showWarning" = false; # disable about:config warning
          "reader.parse-on-load.enabled" = false; # Disable "Reader view"

          "ui.systemUsesDarkTheme" = 1; # Dark theme prefered
          "layout.css.prefers-color-scheme.content-override" = 0; # Force dark mode

          "findbar.modalHighlight" = true;
          "findbar.highlightAll" = true;

          "browser.urlbar.shortcuts.bookmarks" = false;
          "browser.proton.toolbar.version" = 3; # Enable toolbar
          "browser.theme.toolbar-theme" = 0; # Same as above

          "dom.events.asyncClipboard.clipboardItem" = true;

          "network.protocol-handler.external.mailto" = false; # Remove annoying "add application for mailto links"

          # Fix font
          "gfx.font_rendering.cleartype_params.force_gdi_classic_for_families" = "";
          "gfx.font_rendering.cleartype_params.force_gdi_classic_max_size" = 6;
          "gfx.font_rendering.directwrite.use_gdi_table_loading" = false;
          "gfx.font_rendering.cleartype_params.rendering_mode" = 5;

          "gfx.webrender.quality.force-subpixel-aa-where-possible" = true;
          "browser.display.use_document_fonts" = 1; # Enable "Allow pages to choose their own fonts"

          # Privacy
          "privacy.resistFingerprinting" = true; # Instead of using CanvasBlocker extension
          "privacy.resistFingerprinting.pbmode" = true;
          "privacy.resistFingerprinting.autoDeclineNoUserInputCanvasPrompts" = true;

          #"privacy.fingerprintingProtection" = true; # Still want time zone
          #"privacy.fingerprintingProtection.overrides" = "+AllTargets,-JSDateTimeUTC";

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

        search = {
          force = true;

          engines = {
            "SearXNG" = let
              inherit (store-secrets) searxng;
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
          };

          order = [
            "SearXNG"
            "ddg"
            "Brave"
          ];

          default = "SearXNG";
          privateDefault = "ddg";
        };

        # Custom CSS for clean interface
        userChrome = ''

        '';
      };
    };
  };

  systemd.user.services.zen-browser-autostart = {
    Unit = {
      Description = "Start Zen-browser";
      After = ["graphical-session.target"];
    };

    Service = {
      Type = "oneshot";
      ExecStart = "${zen-browser.packages."${pkgs.stdenv.hostPlatform.system}".default}/bin/zen-beta -kiosk ${store-secrets.dashboard}";
    };

    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };
}

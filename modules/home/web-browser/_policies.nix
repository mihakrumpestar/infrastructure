{ lib }:

{
  # Shared Firefox/Mozilla browser policies — hardened baseline
  mkBrowserPolicies =
    {
      extensionUpdate ? true,
      extraPolicies ? { },
    }:
    lib.recursiveUpdate {
      AppAutoUpdate = false; # Disable automatic application update
      BackgroundAppUpdate = false; # Disable automatic application update in the background, when the application is not running
      DisableFirefoxStudies = true;
      DisableFirefoxAccounts = true; # Disable Firefox Sync
      DisableFirefoxScreenshots = true; # No screenshots?
      DisableForgetButton = true; # Thing that can wipe history for X time, handled differently
      DisableMasterPasswordCreation = true; # To be determined how to handle master password
      DisableProfileImport = true; # Purity enforcement: Only allow nix-defined profiles
      DisableProfileRefresh = true; # Disable the Refresh Firefox button on about:support and support.mozilla.org
      DisableSetDesktopBackground = true; # Remove the "Set As Desktop Background..." menuitem when right clicking on an image, because Nix is the only thing that can manage the background
      DisplayMenuBar = "default-off";
      DisablePocket = true;
      DisableTelemetry = true;
      DisableFormHistory = true;
      DisablePasswordReveal = true;
      DontCheckDefaultBrowser = true; # Stop asking for attention
      #HardwareAcceleration = false; # Disabled as it exposes points for fingerprinting # DO NOT USE as it makes all sites slow
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

      inherit extensionUpdate;

      FirefoxSuggest = {
        WebSuggestions = false;
        SponsoredSuggestions = false;
        ImproveSuggest = false;
        Locked = true;
      };
      NoDefaultBookmarks = true;
      PasswordManagerEnabled = false; # Managed by KeePassXC
      PromptForDownloadLocation = true;
      SearchEngines = { }; # This does not apply for some reason, use per profile settings as those work
      SearchSuggestEnabled = false;
      ShowHomeButton = false;
      StartDownloadsInTempDirectory = false;
      UserMessaging = {
        ExtensionRecommendations = false; # Don't recommend extensions while the user is visiting web pages
        FeatureRecommendations = false; # Don't recommend browser features
        Locked = true; # Prevent the user from changing user messaging preferences
        MoreFromMozilla = false; # Don't show the "More from Mozilla" section in Preferences
        SkipOnboarding = true; # Don't show onboarding messages on the new tab page
        UrlbarInterventions = false; # Don't offer suggestions in the URL bar
        WhatsNew = false; # Remove the "What's New" icon and menuitem
      };
      UseSystemPrintDialog = true;
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
        };
      */
    } extraPolicies;

  # Shared Firefox about:config settings — font rendering + UI baseline
  commonBrowserSettings = {
    # Extend
    "extensions.autoDisableScopes" = 0; # Enable profile extensions
    "toolkit.legacyUserProfileCustomizations.stylesheets" = true; # enable userChrome and userContent

    # UI modifications
    "browser.aboutConfig.showWarning" = false; # disable about:config warning
    "reader.parse-on-load.enabled" = false; # Disable "Reader view"

    "ui.systemUsesDarkTheme" = 1; # Dark theme preferred
    "layout.css.prefers-color-scheme.content-override" = 0; # Force dark mode

    "browser.toolbars.bookmarks.visibility" = "never";

    "findbar.modalHighlight" = true;
    "findbar.highlightAll" = true;

    "browser.urlbar.shortcuts.bookmarks" = false;
    "browser.proton.toolbar.version" = 3; # Enable toolbar
    "browser.theme.toolbar-theme" = 0; # Same as above

    "dom.events.asyncClipboard.clipboardItem" = true;

    "network.protocol-handler.external.mailto" = false; # Remove annoying "add application for mailto links"

    # Configure home button behavior
    "browser.startup.homepage_override.mstone" = "ignore";
    "browser.toolbarbuttons.introduced.pocket-button" = false;

    # Session and navigation
    "browser.uidensity" = 1; # Compact mode

    # Privacy
    "privacy.resistFingerprinting" = true; # Instead of using CanvasBlocker extension
    "privacy.resistFingerprinting.pbmode" = true;
    "privacy.resistFingerprinting.autoDeclineNoUserInputCanvasPrompts" = true;

    #"privacy.fingerprintingProtection" = true; # Still want time zone
    #"privacy.fingerprintingProtection.overrides" = "+AllTargets,-JSDateTimeUTC";

    "privacy.donottrackheader.enabled" = true;

    # Fix font
    "gfx.font_rendering.cleartype_params.force_gdi_classic_for_families" = "";
    "gfx.font_rendering.cleartype_params.force_gdi_classic_max_size" = 6;
    "gfx.font_rendering.directwrite.use_gdi_table_loading" = false;
    "gfx.font_rendering.cleartype_params.rendering_mode" = 5;

    "gfx.webrender.quality.force-subpixel-aa-where-possible" = true;
    "browser.display.use_document_fonts" = 1; # Enable "Allow pages to choose their own fonts"

    # Overrides of arkenfox-js

    # override recipe: enable session restore
    "privacy.sanitize.sanitizeOnShutdown" = false;
    "browser.sessionstore.privacy_level" = 0; # 1003 optional to restore cookies/formdata
    "privacy.clearOnShutdown_v2.historyFormDataAndDownloads" = false; # 2811 FF128+

    # override recipe: keep cookies restart
    "privacy.clearOnShutdown_v2.cookiesAndStorage" = false; # Cookies, Site Data, Active Logins [FF128+]
  };
}

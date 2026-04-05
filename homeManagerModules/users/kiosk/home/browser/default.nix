{
  config,
  pkgs,
  vars,
  ...
}: let
  store-secrets = config.my.store-secrets.secrets;
  profileDir = "${config.home.homeDirectory}/.zen/zen-beta/default";
  certImportedMarker = "${profileDir}/.client-cert-imported";

  import-cert-script = pkgs.writeShellApplication {
    name = "import-client-cert";
    runtimeInputs = with pkgs; [nssTools coreutils];
    text = ''
      set -euo pipefail

      if [ -f "${certImportedMarker}" ]; then
        echo "Certificate already imported, skipping..."
        exit 0
      fi

      if [ ! -d "${profileDir}" ]; then
        echo "Profile directory does not exist yet, creating..."
        mkdir -p "${profileDir}"
      fi

      if [ ! -f "${config.age.secrets.client-cert-p12.path}" ]; then
        echo "Certificate file not found"
        exit 1
      fi

      echo "Importing client certificate..."
      pk12util -i "${config.age.secrets.client-cert-p12.path}" -d "${profileDir}" -W ""

      touch "${certImportedMarker}"
      echo "Certificate imported successfully"
    '';
  };
in {
  age.secrets.client-cert-p12 = {
    file = /${vars.secretsDir}/secrets/users/kiosk/client-cert.p12.age;
    path = "${config.home.homeDirectory}/.agenix/secrets/client-cert.p12";
  };

  stylix.targets.zen-browser.profileNames = ["default"];

  programs.zen-browser = {
    enable = true;
    policies = {
      AppAutoUpdate = false;
      BackgroundAppUpdate = false;
      DisableFirefoxStudies = true;
      DisableFirefoxAccounts = true;
      DisableFirefoxScreenshots = true;
      DisableForgetButton = true;
      DisableMasterPasswordCreation = true;
      DisableProfileImport = true;
      DisableProfileRefresh = true;
      DisableSetDesktopBackground = true;
      DisplayMenuBar = "default-off";
      DisablePocket = true;
      DisableTelemetry = true;
      DisableFormHistory = true;
      DisablePasswordReveal = true;
      DontCheckDefaultBrowser = true;
      OfferToSaveLogins = false;
      EnableTrackingProtection = {
        Value = true;
        Locked = true;
        Cryptomining = true;
        Fingerprinting = true;
        EmailTracking = true;
      };
      EncryptedMediaExtensions = {
        Enabled = true;
        Locked = true;
      };
      ExtensionUpdate = false;

      ExtensionSettings = {
        "*" = {
          installation_mode = "blocked";
          blocked_install_message = "Manual extension installation is forbidden!";
        };
      };
    };
    profiles = {
      default = {
        id = 0;
        isDefault = true;
        settings = {
          "browser.startup.homepage" = store-secrets.dashboard;
          "browser.startup.page" = 1;

          "browser.startup.homepage_override.mstone" = "ignore";
          "browser.toolbarbuttons.introduced.pocket-button" = false;

          "browser.uidensity" = 1;

          "browser.toolbars.bookmarks.visibility" = "never";
          "places.history.enabled" = false;

          "extensions.autoDisableScopes" = 0;
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true;

          "reader.parse-on-load.enabled" = false;

          "ui.systemUsesDarkTheme" = 1;
          "layout.css.prefers-color-scheme.content-override" = 0;

          "browser.urlbar.shortcuts.bookmarks" = false;
          "browser.proton.toolbar.version" = 3;
          "browser.theme.toolbar-theme" = 0;

          "network.protocol-handler.external.mailto" = false;

          "gfx.font_rendering.cleartype_params.force_gdi_classic_for_families" = "";
          "gfx.font_rendering.cleartype_params.force_gdi_classic_max_size" = 6;
          "gfx.font_rendering.directwrite.use_gdi_table_loading" = false;
          "gfx.font_rendering.cleartype_params.rendering_mode" = 5;

          "gfx.webrender.quality.force-subpixel-aa-where-possible" = true;
          "browser.display.use_document_fonts" = 1;

          "general.useragent.override" = "Kiosk";

          "security.default_personal_cert" = "Select Automatically";
        };

        userChrome = ''

        '';
      };
    };
  };

  systemd.user.services.import-client-cert = {
    Unit = {
      Description = "Import client certificate into Zen browser profile";
      After = ["graphical-session.target" "agenix.service"];
      Requires = ["agenix.service"];
    };

    Service = {
      Type = "oneshot";
      ExecStart = "${import-cert-script}/bin/import-client-cert";
      RemainAfterExit = true;
    };

    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };

  systemd.user.services.zen-browser-autostart = {
    Unit = {
      Description = "Start Zen-browser";
      After = ["graphical-session.target" "import-client-cert.service"];
      Requires = ["import-client-cert.service"];
    };

    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.zen-browser}/bin/zen-beta -kiosk -private-window ${store-secrets.dashboard}";
    };

    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };
}

{ inputs, ... }:
let
  data = import "${inputs.infrastructure-secrets}/secrets/users/krumpy-miha/data.nix";
in
{
  home.web-browser = {
    homeManager =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        inherit (import ./_policies.nix { inherit lib; }) mkBrowserPolicies commonBrowserSettings;
      in
      {
        home.packages = with pkgs; [
          brave
          ungoogled-chromium
          # ladybird # Build unstable-2025-06-27 fails
        ];

        # Docs:
        # https://github.com/NiXium-org/NiXium/blob/central/src/nixos/users/kira/home/modules/web-browsers/firefox/firefox.nix

        # TODO: https://discourse.nixos.org/t/automatic-firejail-of-home-managers-librewolf-does-not-work/22291

        stylix.targets.librewolf.profileNames = [ "default" ];

        programs.librewolf = {
          enable = true;
          profiles = {
            default = {
              id = 0;
              isDefault = true;
              settings = commonBrowserSettings // {

                "browser.startup.page" = 3; # 0=blank, 1=home, 2=last visited page, 3=resume previous session

                "general.useragent.override" =
                  "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:134.0) Gecko/20100101 Firefox/134.0"; # Does not work when resistFingerprinting is enabled

              };
              #extraConfig = builtins.readFile "${pkgs.arkenfox-userjs}/user.js"; # TODO: this currently overrides our settings above as it applies it later
              userChrome = builtins.readFile ./userChrome.css;
              #extensions = with config.nur.repos.rycee.firefox-addons; [ ];
              search = {
                force = true;
                engines = {
                  "SearXNG" =
                    let
                      inherit (data) searxng;
                    in
                    {
                      id = "searxng";
                      urls = [ { template = "${searxng}/search?q={searchTerms}"; } ];
                      params = [
                        {
                          name = "q";
                          value = "{searchTerms}";
                        }
                      ];
                      definedAliases = [ "@searxng" ];
                      icon = "${searxng}/favicon.ico";
                    };
                  "ddg" = {
                    id = "ddg";
                    urls = [ { template = "https://duckduckgo.com"; } ];
                    params = [
                      {
                        name = "q";
                        value = "{searchTerms}";
                      }
                    ];
                    definedAliases = [ "@d" ];
                    icon = "https://icons.duckduckgo.com/ip3/duckduckgo.com.ico";
                  };
                  "Brave" = {
                    id = "brave";
                    urls = [ { template = "https://search.brave.com/search"; } ];
                    params = [
                      {
                        name = "q";
                        value = "{searchTerms}";
                      }
                    ];
                    definedAliases = [ "@b" ];
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
            };
          };

          nativeMessagingHosts = with pkgs; [
            keepassxc
          ];

          # Docs: https://mozilla.github.io/policy-templates/#extensionsettings
          # Inspiration: https://github.com/NiXium-org/NiXium/blob/central/src/nixos/users/kira/home/modules/web-browsers/firefox/firefox.nix
          policies = mkBrowserPolicies {
            extraPolicies =
              let
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
                  "wappalyzer" = "wappalyzer@crunchlabz.com";
                  "spoof-timezone" = "{55f61747-c3d3-4425-97f9-dfc19a0be23c}";
                  "qr-code-2" = "{9c0bf749-dacb-426c-8f70-882832dc6853}";
                  "addy_io" = "browser-extension@anonaddy";
                };
                mappedExtensions = lib.mapAttrs' (
                  name: id:
                  lib.nameValuePair id {
                    install_url = "https://addons.mozilla.org/firefox/downloads/latest/${name}/latest.xpi";
                    installation_mode = "normal_installed"; # Allow disabling, auto-install
                    default_area = "navbar"; # Pinned (only applies on first start)
                  }
                ) extensions;
              in
              {
                ExtensionSettings = {
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
              };
          };
        };

        systemd.user.services.cleanup-sidebery-downloads = {
          Unit = {
            Description = "Cleanup old Sidebery downloads, keeping 120 most recent";
          };
          Service = {
            Type = "oneshot";
            ExecStart = toString (
              pkgs.writeShellScript "cleanup-sidebery-downloads" ''
                DIR="${config.home.homeDirectory}/Downloads/Sidebery"
                KEEP=120

                if [ -d "$DIR" ]; then
                  cd "$DIR" || exit 1
                  file_count=$(find . -type f | wc -l)
                  if [ "$file_count" -gt "$KEEP" ]; then
                    to_delete=$((file_count - KEEP))
                    find . -type f -printf '%T@ %p\0' | sort -zrn | tail -z -n +$((KEEP + 1)) | cut -z -d' ' -f2- | xargs -0 -r rm -f --
                    echo "Deleted $to_delete files from Sidebery downloads"
                  else
                    echo "Only $file_count files, nothing to delete"
                  fi
                else
                  echo "Directory $DIR does not exist"
                fi
              ''
            );
          };
        };

        systemd.user.timers.cleanup-sidebery-downloads = {
          Unit = {
            Description = "Run cleanup-sidebery-downloads daily";
          };
          Timer = {
            OnCalendar = "daily";
            Persistent = true;
          };
          Install = {
            WantedBy = [ "timers.target" ];
          };
        };
      };
  };
}

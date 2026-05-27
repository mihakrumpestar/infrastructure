{ inputs, ... }:
let
  secretsDir = inputs.infrastructure-secrets;
  data = import "${secretsDir}/secrets/users/kiosk/data.nix";
in
{
  home.kiosk-browser = {
    homeManager =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        inherit (import ../web-browser/_policies.nix { inherit lib; })
          mkBrowserPolicies
          commonBrowserSettings
          ;

        profileDir = "${config.home.homeDirectory}/.librewolf/default";
        certImportedMarker = "${profileDir}/.client-cert-imported";

        import-cert-script = pkgs.writeShellApplication {
          name = "import-client-cert";
          runtimeInputs = with pkgs; [
            nssTools
            coreutils
          ];
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
      in
      {
        age.secrets.client-cert-p12 = {
          file = "${secretsDir}/secrets/users/kiosk/client-cert.p12.age";
          path = "${config.home.homeDirectory}/.agenix/secrets/client-cert.p12";
        };

        stylix.targets.librewolf.profileNames = [ "default" ];

        programs.librewolf = {
          enable = true;
          policies = mkBrowserPolicies {
            extraPolicies = {

              ExtensionSettings = {
                "*" = {
                  installation_mode = "blocked";
                  blocked_install_message = "Manual extension installation is forbidden!";
                };
              };
            };
          };
          profiles = {
            default = {
              id = 0;
              isDefault = true;
              settings = commonBrowserSettings // {
                # Kiosk-specific
                "browser.startup.homepage" = data.dashboard;
                "browser.startup.page" = 1; # Always start with homepage

                "places.history.enabled" = false;

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
            Description = "Import client certificate into Librewolf profile";
            After = [
              "graphical-session.target"
              "agenix.service"
            ];
            Requires = [ "agenix.service" ];
          };
          Service = {
            Type = "oneshot";
            ExecStart = "${import-cert-script}/bin/import-client-cert";
            RemainAfterExit = true;
          };
          Install = {
            WantedBy = [ "graphical-session.target" ];
          };
        };

        systemd.user.services.librewolf-autostart = {
          Unit = {
            Description = "Start Librewolf";
            After = [
              "graphical-session.target"
              "import-client-cert.service"
            ];
            Requires = [ "import-client-cert.service" ];
          };
          Service = {
            Type = "oneshot";
            ExecStart = "${pkgs.librewolf}/bin/librewolf -kiosk -private-window ${data.dashboard}";
          };
          Install = {
            WantedBy = [ "graphical-session.target" ];
          };
        };
      };
  };
}

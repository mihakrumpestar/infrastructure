{ ... }:
{
  home.task-app.homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfgDir = "${config.xdg.configHome}/superProductivity";
      settingsFile = "${cfgDir}/simpleSettings";
      restTokenFile = "${cfgDir}/local-rest-api-token";
      inherit (pkgs) coreutils;

      # Agent-facing CLI over the local REST API. Reads the token from
      # `restTokenFile`; `spt --help` carries the whole interface.
      spt = pkgs.writeShellApplication {
        name = "spt";
        runtimeInputs = [ pkgs.bun ];
        text = ''
          exec bun ${./spt.ts} "$@"
        '';
      };
    in
    {
      options.my.home.taskApp.restApi = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable the loopback REST API used by the `spt` CLI.";
        };

        token = lib.mkOption {
          type = lib.types.strMatching "[A-Za-z0-9]{32}";
          default = "sptLocalhostRestApi0000000000000";
          description = ''
            Bearer token for the local REST API. The app accepts exactly 32
            alphanumeric characters; anything else makes it mint its own.
            This value is also embedded in the world-readable home-manager
            activation script, so it is not a secret on this machine.
          '';
        };
      };

      config = {
        home.packages = [
          pkgs.super-productivity
          spt
        ];

        # The app reads `localRestApiEnabled`, the token and the assistant
        # switch only at startup, so a switch needs an app restart to take
        # effect. Unrelated keys in `simpleSettings` are preserved; the file is
        # replaced atomically so a concurrent app read cannot see a half-written
        # config. A non-object file is backed up and rebuilt.
        #
        # The built-in MCP endpoint is switched off: `spt` over REST is the
        # only agent path. Its old verifier file is left alone if present.
        home.activation.superProductivityRestApi = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          set -eu

          if [ -n "''${DRY_RUN_CMD:-}" ]; then
            echo "super-productivity: dry run, not writing REST settings"
          else
            ${coreutils}/bin/install -d -m 700 "${cfgDir}"

          if [ -d "${settingsFile}" ]; then
            ${coreutils}/bin/mv "${settingsFile}" "${settingsFile}.dir-$(${coreutils}/bin/date +%s%N)"
          fi

          if [ -s "${settingsFile}" ] && ! ${pkgs.jq}/bin/jq -e 'type == "object"' "${settingsFile}" >/dev/null 2>&1; then
            backup="${settingsFile}.invalid-$(${coreutils}/bin/date +%s%N)"
            ${coreutils}/bin/cp -f "${settingsFile}" "$backup"
            echo "super-productivity: simpleSettings was not a JSON object, backed up to $backup" >&2
            ${coreutils}/bin/rm -f "${settingsFile}"
          fi

          tmp="$(${coreutils}/bin/mktemp "${cfgDir}/.simpleSettings.XXXXXX")"
          if [ -s "${settingsFile}" ]; then
            ${pkgs.jq}/bin/jq \
              --argjson rest '${lib.boolToString config.my.home.taskApp.restApi.enable}' \
              '.assistantAccess = { isEnabled: false, scopes: [] }
               | .localRestApiEnabled = $rest' \
              "${settingsFile}" > "$tmp"
          else
            ${pkgs.jq}/bin/jq \
              --argjson rest '${lib.boolToString config.my.home.taskApp.restApi.enable}' \
              -n '{ assistantAccess: { isEnabled: false, scopes: [] }, localRestApiEnabled: $rest }' > "$tmp"
          fi
          ${coreutils}/bin/chmod 600 "$tmp"
          ${coreutils}/bin/mv -f "$tmp" "${settingsFile}"

          if ${lib.boolToString config.my.home.taskApp.restApi.enable}; then
            tmp="$(${coreutils}/bin/mktemp "${cfgDir}/.local-rest-api-token.XXXXXX")"
            printf '%s' ${lib.escapeShellArg config.my.home.taskApp.restApi.token} > "$tmp"
            ${coreutils}/bin/chmod 600 "$tmp"
            ${coreutils}/bin/mv -f "$tmp" "${restTokenFile}"
          else
            ${coreutils}/bin/rm -f "${restTokenFile}"
          fi

          if ${pkgs.procps}/bin/pgrep -f 'superproductivity' >/dev/null 2>&1; then
            echo "super-productivity: restart the app to apply the REST settings and token" >&2
          fi
          fi
        '';
      };
    };
}

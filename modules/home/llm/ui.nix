{ ... }:
{
  home.llm-ui = {
    homeManager =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        cfg = config.my.llm;
        host = cfg.opencodeServerHost;
        urlHost = if lib.hasInfix ":" host then "[${host}]" else host;
      in
      {
        programs.t3code = {
          enable = true;
          package = pkgs.t3code.override {
            enableOpencode = true;
            opencode = config.programs.opencode.package;
          };

          userSettings = {
            defaultModelSelection = {
              instanceId = "opencode";
              model = config.programs.opencode.settings.model;
            };
            defaultRuntimeMode = "auto";
            sourceControlWritingStyle.mode = "conventional_commits";

            backgroundActivity = {
              profile = "custom";
              overrides.automaticGitFetchInterval = 0;
            };

            # Use the server that already loads the gateway and MCP environment.
            providerInstances.opencode = {
              driver = "opencode";
              enabled = true;
              config = {
                serverUrl = "http://${urlHost}:${toString cfg.opencodeServerPort}";
                serverPassword = cfg.opencodeServerPassword;
              };
            };
          };

          clientSettings = {
            notificationMode = "notifications-and-sound";
            inAppNotificationsEnabled = true;
            browserSearchEngine = "brave";
            followUpBehavior = "queue";
            threadDetailsUsageEnabled = true;
            chatWidth = "wide";
            timestampFormat = "24-hour";
            confirmThreadDelete = true;
          };
        };
      };
  };
}

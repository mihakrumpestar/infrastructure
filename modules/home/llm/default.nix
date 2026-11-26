{ home, inputs, ... }:
let
  userSecrets = "${inputs.infrastructure-secrets}/secrets/sops/krumpy-miha.yaml";
in
{
  home.llm = {
    includes = [
      home.llm-agent
      home.llm-ui
    ];

    homeManager =
      { config, lib, ... }:
      {
        options.my.llm.openchamberDrex.enable =
          lib.mkEnableOption "OpenChamber's Drex classifier using llm/openchamber_drex_api_key";

        config.sops = {
          secrets = {
            llm_agent_env = {
              sopsFile = userSecrets;
              key = "llm/agent_env";
            };

            # Do not require the new key until credentials have been provisioned.
            openchamber_drex_api_key = lib.mkIf config.my.llm.openchamberDrex.enable {
              sopsFile = userSecrets;
              key = "llm/openchamber_drex_api_key";
            };
          };

          templates."openchamber-drex-endpoint.json" = lib.mkIf config.my.llm.openchamberDrex.enable {
            content = builtins.toJSON {
              version = 1;
              endpoint = {
                url = "https://console.nace.ai/v1/systemone";
                model = "drex-latest";
                key = config.sops.placeholder.openchamber_drex_api_key;
              };
            };
          };
        };
      };
  };
}

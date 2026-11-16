{ home, inputs, ... }:
let
  secretsDir = inputs.infrastructure-secrets;
in
{
  home.llm = {
    includes = [
      home.llm-agent
      home.llm-ui
    ];

    homeManager = {
      sops.secrets.llm_agent_env = {
        sopsFile = "${secretsDir}/secrets/sops/krumpy-miha.yaml";
        key = "llm/agent_env";
      };
    };
  };
}

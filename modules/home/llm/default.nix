{ home, inputs, ... }:
let
  secretsDir = inputs.infrastructure-secrets;
in
{
  home.llm = {
    includes = [
      home.llm-agent
      home.llm-mcp
      home.llm-ui
    ];

    # One declaration for the aspects below: the agent (web service env), the
    # MCP wrappers and the OpenChamber classifier all read this file.
    homeManager =
      { config, ... }:
      {
        age.secrets."llm_agent.env" = {
          file = "${secretsDir}/secrets/users/krumpy-miha/llm_agent.env.age";
          path = "${config.home.homeDirectory}/.agenix/secrets/llm_agent.env";
        };
      };
  };
}

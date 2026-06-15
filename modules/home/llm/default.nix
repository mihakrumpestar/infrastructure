{ home, ... }:
{
  home.llm = {
    includes = [
      home.llm-agent
      home.llm-gateway
      home.llm-mcp
    ];
  };
}

{ home, ... }:
{
  home.llm = {
    includes = [
      home.llm-agent
      home.llm-mcp
      home.llm-ui
    ];
  };
}

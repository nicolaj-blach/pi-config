{
  description = "pi coding agent configuration (Home Manager module)";

  inputs = {
    # pi and other coding agents, updated daily; no follows so cache.numtide.com hits
    llm-agents.url = "github:numtide/llm-agents.nix";
    agent-markdown-files = {
      url = "github:nicolaj-blach/agent-markdown-files";
      flake = false;
    };
  };

  outputs = inputs: {
    homeManagerModules.default = import ./module.nix inputs;
  };
}

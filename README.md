# pi-config

Home Manager module for the [pi](https://github.com/badlogic/pi-mono) coding agent: the
`pi` wrapper, `pi-assistant`, settings, packages, keybindings, OneDark theme, startup
header and permissions. Markdown (AGENTS.md, agents, skills) comes from
[agent-markdown-files](https://github.com/nicolaj-blach/agent-markdown-files).

```nix
imports = [ inputs.pi-config.homeManagerModules.default ];
programs.pi-coding-agent.enable = true;
pi-config.logo = ./logo.svg;
```

After changing something, push and run `nix flake update pi-config` in `~/nixos`.

# pi from llm-agents.nix, configured through Home Manager's pi module. ~/.pi/agent
# is read-only; markdown (AGENTS.md, agents, skills) lives in agent-markdown-files.
inputs:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.pi-coding-agent;
  md = inputs.agent-markdown-files;
  json = pkgs.formats.json { };
  pi = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.pi;

  # Startup header extension with the logo rendered for kitty graphics.
  # Solid background because ghostel drops alpha.
  header = pkgs.runCommand "pi-header" { nativeBuildInputs = [ pkgs.librsvg ]; } ''
    mkdir $out
    cp ${./files/header/index.ts} $out/index.ts
    rsvg-convert -w 320 -h 286 --background-color '#282c34' \
      ${config.pi-config.logo} -o $out/logo.png
  '';

  # Quiet the npm installs pi runs for its packages (warnings, funding, audit)
  npmrc = pkgs.writeText "pi-npmrc" ''
    loglevel=error
    fund=false
    audit=false
    update-notifier=false
  '';

  # settings.json is read-only, so pi can't save the default model: start on the
  # model the most recent session last switched to, unless one is given.
  # PI_CODING_AGENT_SESSION_DIR keeps the assistant's sessions (and model) separate.
  lastModel = pkgs.writeShellScript "pi-last-model" ''
    dir=''${PI_CODING_AGENT_SESSION_DIR:-$HOME/.pi/agent/sessions}
    f=$(ls -t "$dir"/*.jsonl "$dir"/*/*.jsonl 2>/dev/null | head -n1)
    [ -n "$f" ] || exit 0
    ${lib.getExe pkgs.jq} -r 'select(.type == "model_change") | "\(.provider)/\(.modelId)"' "$f" | tail -n1
  '';

  # pi-vim only outside Emacs: inside ghostel, evil owns Esc
  piVim = pkgs.writeShellScriptBin "pi" ''
    export NPM_CONFIG_USERCONFIG=${npmrc}
    case " $* " in
      *" --model "* | *" --model="* | *" -c "* | *" --continue "* | *" -r "* | *" --resume "* | *" --session "*) ;;
      *) m=$(${lastModel}); [ -n "$m" ] && set -- --model "$m" "$@" ;;
    esac
    [ -n "''${INSIDE_EMACS:-}" ] || set -- -e npm:pi-vim@0.14.2 "$@"
    exec ${lib.getExe pi} "$@"
  '';

  # General-purpose assistant (Mod+A): own prompt and sessions, read-only file
  # tools plus web search and fetch (pi-web-access)
  piAssistant = pkgs.writeShellScriptBin "pi-assistant" ''
    export PI_CODING_AGENT_SESSION_DIR="$HOME/.pi/agent/sessions-assistant"
    cd "$HOME"
    # The installed pi (Home Manager wraps it with nodejs on PATH)
    exec pi \
      --system-prompt "$(cat ${md}/assistant.md)" \
      --no-context-files --no-skills \
      --tools read,grep,find,ls,web_search,fetch_content,get_search_content \
      "$@"
  '';

  # Ctrl+G: the current Emacs frame inside ghostel, a new frame elsewhere
  editor = pkgs.writeShellScript "pi-editor" ''
    [ -n "''${INSIDE_EMACS:-}" ] && exec emacsclient "$@"
    exec emacsclient -c "$@"
  '';
in
{
  imports = [ ./hm-module.nix ];

  options.pi-config.logo = lib.mkOption {
    type = lib.types.path;
    description = "SVG logo shown in the startup header.";
  };

  config = lib.mkIf cfg.enable {
    programs.pi-coding-agent = {
      package = piVim;
      extraPackages = [ pkgs.nodejs ];
      context = "${md}/AGENTS.md";

      settings = {
        theme = "onedark";
        tuiMode = "regular";
        externalEditor = "${editor}";
        quietStartup = true;
        collapseChangelog = true;
        enableInstallTelemetry = false;
        doubleEscapeAction = "none";
        piVim.clipboardMirror = "all";
        skills = [ "${md}/skills" ];
        extensions = [ "${header}" ];
        # The header extension replaces powerline's welcome; its status bar stays
        powerline.welcome = false;
        # Installed by pi into ~/.pi/agent/npm on first start
        packages = [
          "npm:pi-subagents@0.75.0"
          "npm:pi-web-access@0.35.0"
          "npm:@juicesharp/rpiv-ask-user-question@2.12.0"
          "npm:@juicesharp/rpiv-todo@2.12.0"
          "npm:pi-lens@4.3.0"
          "npm:@gotgenes/pi-permission-system@39.0.3"
          "npm:plan-mode-lite@0.1.7"
          "npm:pi-powerline-footer@0.19.1"
        ];
      };

      keybindings = {
        # Shift+Tab toggles plan mode
        "app.thinking.cycle" = "alt+t";
        # Vim-style movement in pickers (they filter as you type, so plain j/k can't work)
        "tui.select.up" = [
          "up"
          "ctrl+k"
        ];
        "tui.select.down" = [
          "down"
          "ctrl+j"
        ];
      };
    };

    home.file = {
      ".pi/agent/themes/onedark.json".source = ./files/onedark.json;
      # User scope, so same-name agents (reviewer) replace pi-subagents' built-ins
      ".pi/agent/agents".source = "${md}/agents";
      ".pi/agent/plan-mode-lite.json".source = json.generate "plan-mode-lite.json" {
        defaultOn = false;
        toggleShortcut = "shift+tab";
      };
      # Last match wins inside each map; across layers deny beats ask beats allow
      ".pi/agent/extensions/pi-permission-system/config.json".source =
        json.generate "pi-permissions.json"
          {
            permission = {
              "*" = "allow";
              path = {
                "*" = "allow";
                "~/.ssh/*" = "deny";
                "~/.gnupg/*" = "deny";
                "~/.config/sops/*" = "deny";
                "/run/secrets/*" = "deny";
                "/run/secrets.d/*" = "deny";
                "*.env" = "deny";
                "*.env.*" = "deny";
                "*.env.example" = "allow";
              };
              bash = {
                "*" = "allow";
                "rm -r *" = "ask";
                "rm -rf *" = "ask";
                "rm -fr *" = "ask";
                "rm -R *" = "ask";
                "sudo *" = "ask";
                "git push*" = "ask";
                "git reset --hard*" = "ask";
                "git clean*" = "ask";
                "git checkout -- *" = "ask";
                "npm install -g *" = "ask";
                "npm i -g *" = "ask";
                "pip install *" = "ask";
                "cargo install *" = "ask";
                "go install *" = "ask";
                "nix profile install *" = "ask";
              };
              external_directory = {
                "*" = "ask";
                "~/nixos/*" = "allow";
                "~/projects/personal/agent-markdown-files/*" = "allow";
                "~/projects/personal/pi-config/*" = "allow";
                "/tmp/*" = "allow";
                "/nix/store/*" = "allow";
              };
            };
          };
    };

    home.packages = [ piAssistant ];
  };
}

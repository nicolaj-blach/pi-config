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

  # Focus the pi with PID $1: its ghostel buffer (and Emacs frame) or its kitty window
  focus = pkgs.writeShellScript "pi-focus" ''
    PATH=${lib.makeBinPath [ pkgs.jq pkgs.procps ]}:$PATH
    pids="" p=$1
    while [ -n "$p" ] && [ "$p" -gt 1 ]; do
      pids="$pids $p"
      p=$(ps -o ppid= -p "$p" | tr -d ' ')
    done
    windows=$(niri msg -j windows) || exit 0
    if [ -n "''${INSIDE_EMACS:-}" ]; then
      frame=$(emacsclient -e "
        (let ((buf (seq-find (lambda (b)
                               (with-current-buffer b
                                 (and (derived-mode-p 'ghostel-mode)
                                      (memq ghostel--pid '($pids)))))
                             (buffer-list))))
          (when buf
            (let* ((win (get-buffer-window buf t))
                   (frame (if win (window-frame win) (selected-frame))))
              (select-frame-set-input-focus frame)
              (if win (select-window win) (pop-to-buffer buf))
              (frame-parameter frame 'name))))" | sed 's/^"//;s/"$//')
      id=$(jq -r --arg t "$frame" '
        (map(select(.app_id == "emacs" and .title == $t)) + map(select(.app_id == "emacs")))
        | .[0].id // empty' <<<"$windows")
    else
      id=$(jq -r --arg p "$pids" '
        ($p | split(" ") | map(select(. != "") | tonumber)) as $ps
        | map(select(.pid as $w | $ps | index($w))) | .[0].id // empty' <<<"$windows")
    fi
    [ -n "$id" ] && niri msg action focus-window --id "$id"
  '';

  status = pkgs.runCommand "pi-status" { } ''
    mkdir $out
    substitute ${./files/status/index.ts} $out/index.ts \
      --replace-fail @notifySend@ ${lib.getExe' pkgs.libnotify "notify-send"} \
      --replace-fail @focus@ ${focus}
  '';

  # Patched npm packages for vim keys where they are hardcoded. Local packages,
  # so pi doesn't install their dependencies: bundle them (none have their own).
  npmTgz =
    name: version: hash:
    pkgs.fetchurl {
      url = "https://registry.npmjs.org/${name}/-/${baseNameOf name}-${version}.tgz";
      inherit hash;
    };
  patchedNpm =
    {
      name,
      version,
      hash,
      deps ? [ ],
      patch,
    }:
    pkgs.runCommand "${baseNameOf name}-${version}-vim" { nativeBuildInputs = [ pkgs.patch ]; } ''
      mkdir $out
      tar -xzf ${npmTgz name version hash} -C $out --strip-components=1
      ${lib.concatMapStrings (d: ''
        mkdir -p $out/node_modules/${d.name}
        tar -xzf ${npmTgz d.name d.version d.hash} -C $out/node_modules/${d.name} --strip-components=1
      '') deps}
      patch -d $out -p1 < ${patch}
    '';

  # hjkl in question dialogs
  askUserQuestion = patchedNpm {
    name = "@juicesharp/rpiv-ask-user-question";
    version = "2.12.0";
    hash = "sha512-DilWc7u25SwnK6ytuAWOTerP0AmOEfK4HXpgS1oEzkgv9d5g5T+PbLG+zcLn18M3B/J3poMG14iydG5O6iBsnw==";
    deps = [
      {
        name = "@juicesharp/rpiv-config";
        version = "2.12.0";
        hash = "sha512-eGjoCDCKz2JtKIUIpZ2y8CAVjxZYXCKa2D64ByozhkAWVblXsgyFLrQMk5k5Bv5RXRrA3GY66XNG5ExtEuGASA==";
      }
    ];
    patch = ./files/ask-user-question/hjkl.patch;
  };

  # Ctrl+J/K instead of the arrows for the FleetView under the editor
  subagents = patchedNpm {
    name = "pi-subagents";
    version = "0.75.0";
    hash = "sha512-RO4DiTJM6pnK8y9PnD7Y6TLeiX2c8Kh6QhmkecFo+ou5qtnz5qiM+vUKru48UmJG1nB9eJ6rALd1M04uBOR4XQ==";
    deps = [
      {
        name = "acorn";
        version = "8.18.0";
        hash = "sha512-lGq+9yr1/GuAWaVYIHRjvvySG5/4VfKIvC8EWxStPdcDh/Ka7FG3twP6v4d5BkravUilhIAsG4Qj83t02LWUPQ==";
      }
      {
        name = "jiti";
        version = "2.7.0";
        hash = "sha512-AC/7JofJvZGrrneWNaEnJeOLUx+JlGt7tNa0wZiRPT4MY1wmfKjt2+6O2p2uz2+skll8OZZmJMNqeke7kKbNgQ==";
      }
      {
        name = "undici";
        version = "8.10.2";
        hash = "sha512-/y4/bH9YNU5hi9NIrpOuvGXFcxrj3CMrV+/AYpowAYTpHn8gX/XPFjNy766FPoYY0miQhdW977JFWKGNhBdwyQ==";
      }
      {
        name = "yaml";
        version = "2.8.3";
        hash = "sha512-AvbaCLOO2Otw/lW5bmh9d/WEdcDFdQp2Z2ZUH3pX9U2ihyUY0nvLv7J6TrWowklRGPYbB/IuIMfYgxaCPg5Bpg==";
      }
    ];
    patch = ./files/subagents/ctrl-jk.patch;
  };

  # Quiet the npm installs pi runs for its packages (warnings, funding, audit)
  npmrc = pkgs.writeText "pi-npmrc" ''
    loglevel=error
    fund=false
    audit=false
    update-notifier=false
  '';

  # settings.json is read-only, so pi can't save the default model: start on the
  # model and thinking level the most recent session last switched to, unless given.
  # PI_CODING_AGENT_SESSION_DIR keeps the assistant's sessions (and model) separate.
  # $1 is "model" or "thinking".
  lastSetting = pkgs.writeShellScript "pi-last-setting" ''
    dir=''${PI_CODING_AGENT_SESSION_DIR:-$HOME/.pi/agent/sessions}
    f=$(ls -t -- "$dir"/*.jsonl "$dir"/*/*.jsonl 2>/dev/null | head -n1)
    [ -n "$f" ] || exit 0
    case $1 in
      model) q='select(.type == "model_change") | "\(.provider)/\(.modelId)"' ;;
      thinking) q='select(.type == "thinking_level_change") | .thinkingLevel' ;;
    esac
    ${lib.getExe pkgs.jq} -r "$q" "$f" | tail -n1
  '';

  # pi-vim only outside Emacs: inside ghostel, evil owns Esc
  piVim = pkgs.writeShellScriptBin "pi" ''
    export NPM_CONFIG_USERCONFIG=${npmrc}
    case " $* " in
      *" -c "* | *" --continue "* | *" -r "* | *" --resume "* | *" --session "*) ;;
      *)
        case " $* " in
          *" --model "* | *" --model="*) ;;
          *) m=$(${lastSetting} model); [ -n "$m" ] && set -- --model "$m" "$@" ;;
        esac
        case " $* " in
          *" --thinking "* | *" --thinking="*) ;;
          *) t=$(${lastSetting} thinking); [ -n "$t" ] && set -- --thinking "$t" "$@" ;;
        esac
        ;;
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
        extensions = [
          "${header}"
          "${./files/last-model}"
          "${status}"
          "${./files/handoff}"
        ];
        # The header extension replaces powerline's welcome; its status bar stays
        powerline.welcome = false;
        # Installed by pi into ~/.pi/agent/npm on first start
        packages = [
          "${subagents}"
          "npm:pi-web-access@0.35.0"
          "${askUserQuestion}"
          "npm:@juicesharp/rpiv-todo@2.12.0"
          "npm:pi-lens@4.3.0"
          "npm:@gotgenes/pi-permission-system@39.0.3"
          "npm:plan-mode-lite@0.1.7"
          "npm:pi-powerline-footer@0.19.1"
          "npm:pi-mono-btw@1.7.4"
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
        # /tree: H/L jump between branches (the search ignores case); labels move to E
        "app.tree.foldOrUp" = [
          "ctrl+left"
          "alt+left"
          "shift+h"
        ];
        "app.tree.unfoldOrDown" = [
          "ctrl+right"
          "alt+right"
          "shift+l"
        ];
        "app.tree.editLabel" = "shift+e";
      };
    };

    home.file = {
      ".pi/agent/themes/onedark.json".source = ./files/onedark.json;
      # User scope, so same-name agents (reviewer) replace pi-subagents' built-ins
      ".pi/agent/agents".source = "${md}/agents";
      # Fleet inspector: hjkl, g/G; J/K keep scrolling the transcript
      ".pi/agent/extensions/subagent/config.json".source = json.generate "pi-subagents.json" {
        fleetKeybindings = {
          selectUp = [
            "up"
            "k"
          ];
          selectDown = [
            "down"
            "j"
          ];
          inspect = [
            "return"
            "l"
          ];
          close = [
            "escape"
            "q"
            "h"
          ];
          selectFirst = [
            "home"
            "g"
          ];
          selectLast = [
            "end"
            "G"
          ];
        };
      };
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
                "~/setup/*" = "allow";
                "/tmp/*" = "allow";
                "/nix/store/*" = "allow";
              };
            };
          };
    };

    home.packages = [ piAssistant ];
  };
}

{ ... }:
{
  home.ide = {
    homeManager =
      { config, pkgs, ... }:
      let
        vscode-ltex-plus-offline = pkgs.vscode-utils.buildVscodeMarketplaceExtension rec {
          mktplcRef = {
            name = "vscode-ltex-plus";
            version = "15.6.1";
            publisher = "ltex-plus";
          };
          vsix = builtins.fetchurl {
            url = "https://github.com/ltex-plus/vscode-ltex-plus/releases/download/${mktplcRef.version}/vscode-ltex-plus-${mktplcRef.version}-offline-linux-x64.vsix";
            sha256 = "09jp99vcafj83d4s5p8d9f2k2znv96ig9awhr4mdn4qnx8081qdy";
          };
        };
        gomplate-delimiter-patch = pkgs.writeText "patch-gomplate-delimiters.py" ''
          import copy
          import plistlib
          import sys

          path = sys.argv[1]
          with open(path, "rb") as grammar_file:
              grammar = plistlib.load(grammar_file)

          patterns = grammar["patterns"]
          if any(pattern.get("begin") == r"\[\[" for pattern in patterns):
              raise SystemExit(0)

          template = next(
              (pattern for pattern in patterns if pattern.get("begin") == r"\{\{"),
              None,
          )
          if template is None:
              raise SystemExit(f"no {{{{ }}}} pattern in {path}")

          square = copy.deepcopy(template)
          square["begin"] = r"\[\["
          square["end"] = r"\]\]"
          patterns.append(square)

          grammar["foldingStartMarker"] = r"(?:\{\{|\[\[)\s*(?:if|with|range)\b"
          grammar["foldingStopMarker"] = r"(?:\{\{|\[\[)\s*(?:else|end)\b"

          with open(path, "wb") as grammar_file:
              plistlib.dump(grammar, grammar_file)
        '';
        # xembly's Go-template injection lists YAML, JSON, CSS and others but
        # not TOML. Add it so *.toml.gotmpl keeps TOML highlighting while still
        # highlighting the Go template actions. The file association lives in
        # vscode-settings.jsonc.
        gomplate-toml-injection-patch = pkgs.writeText "patch-gomplate-toml-injection.py" ''
          import json
          import sys

          package_path, injection_path = sys.argv[1], sys.argv[2]

          with open(package_path) as package_file:
              package = json.load(package_file)

          for grammar in package["contributes"]["grammars"]:
              if grammar.get("scopeName") == "gomplate.injection":
                  inject_to = grammar.setdefault("injectTo", [])
                  if "source.toml" not in inject_to:
                      inject_to.append("source.toml")
                  break
          else:
              raise SystemExit(f"no gomplate.injection grammar in {package_path}")

          with open(package_path, "w") as package_file:
              json.dump(package, package_file, indent=2)
              package_file.write("\n")

          with open(injection_path) as injection_file:
              injection = json.load(injection_file)

          selector = injection["injectionSelector"]
          if "L:source.toml" not in selector:
              injection["injectionSelector"] = selector + ", L:source.toml"

          with open(injection_path, "w") as injection_file:
              json.dump(injection, injection_file, indent=2)
              injection_file.write("\n")
        '';
        # goyaml embeds YAML plus Go template; patch its grammar for the custom
        # [[ ]] delimiters used by the Nomad templates.
        xembly-gomplate = pkgs.vscode-marketplace.xembly.gomplate.overrideAttrs (old: {
          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.python3 ];
          postInstall = (old.postInstall or "") + ''
            extension="$out/share/vscode/extensions/xembly.gomplate"
            chmod u+w "$extension/package.json" \
              "$extension/syntaxes/gomplate-injection.tmLanguage.json" \
              "$extension/syntaxes/gomplate.tmLanguage"
            python3 ${gomplate-delimiter-patch} \
              "$extension/syntaxes/gomplate.tmLanguage"
            python3 ${gomplate-toml-injection-patch} \
              "$extension/package.json" \
              "$extension/syntaxes/gomplate-injection.tmLanguage.json"
          '';
        });
        # Cloudflare's `cf` stores OAuth credentials encrypted with a key kept
        # in the OS keyring. On Linux that backend is `secret-tool`, which is
        # not part of cf's runtime PATH, and keyring use is opt-in via env.
        cf-keyring = pkgs.symlinkJoin {
          name = "cf-keyring";
          paths = [ pkgs.cf ];
          nativeBuildInputs = [ pkgs.makeWrapper ];
          postBuild = ''
            for binary in cf cloudflare; do
              wrapProgram $out/bin/$binary \
                --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.libsecret ]} \
                --set-default CLOUDFLARE_AUTH_USE_KEYRING true
            done
          '';
          meta.mainProgram = "cf";
        };
      in
      {
        # This are ment for system, not projects
        home.packages = with pkgs; [
          # Latex
          tex-fmt
          texliveFull # Containes pdflatex and Tex packages required by xournalpp (full is the minimum req to run)
          python313Packages.pygments # For Latex code snippets

          # Typst
          typst

          # Python
          python3
          uv

          # Nix
          nixd # Language server
          nixfmt # Formatter

          # Javascript
          bun
          nodejs

          # Markdown
          mermaid-cli

          # Git
          git
          git-filter-repo
          # Authenticated once with:
          # gh auth login
          github-cli

          # Cloudflare, usage examples:
          # cf auth create work        # interactive sign-in, also creates the profile
          # cf auth create personal
          # cf auth activate work ~/Projects/work
          # cf auth activate personal ~/Projects/personal
          # cf auth list
          cf-keyring

          yaak # TODO: test
          scc
          bruno
          devbox
        ];

        home.sessionVariables = {
          CGO_ENABLED = "0"; # Disable use of CGO

          # Disable Github CLI telemetry
          GH_TELEMETRY = "false";
          DO_NOT_TRACK = "true";
        };

        # For uv, go, etc. installables
        home.sessionPath = [
          "${config.home.homeDirectory}/.local/bin"
        ];

        # devenv: per-project dev environments; the zsh integration activates
        # them on cd and the VS Code extension mirrors the env into the editor.
        programs.devenv = {
          enable = true;
          enableZshIntegration = true;
        };

        xdg.configFile."secretspec/config.toml".text = ''
          [defaults]
          provider = "keyring"
          profile = "default"
        '';

        programs.vscodium = {
          enable = true;
          mutableExtensionsDir = false;
          profiles.default = {
            extensions =
              with pkgs.open-vsx;
              [
                # find them on https://open-vsx.org/ # or "vscode-marketplace"
                # (note that all characters have to be converted to lower case if they are not already)
                #
                # General
                activitywatch.aw-watcher-vscode
                vscode-icons-team.vscode-icons
                donjayamanne.githistory
                edwinhuish.better-comments-next
                waderyan.gitblame
                github.github-vscode-theme
                hediet.vscode-drawio
                jeanp413.open-remote-ssh
                matthewpi.caddyfile-support
                pomdtr.excalidraw-editor
                redhat.vscode-yaml
                ritwickdey.liveserver
                #streetsidesoftware.code-spell-checker
                tamasfe.even-better-toml
                tumido.cron-explained
                mathematic.vscode-pdf # VSCode does not have native PDF support for some reason

                # Latex
                james-yu.latex-workshop

                # Go
                golang.go
                # goyaml embeds YAML plus Go template; not on Open VSX
                xembly-gomplate

                # Python
                detachhead.basedpyright
                charliermarsh.ruff
                ms-python.python # Required by Ruff

                # Docker
                docker.docker
                ms-azuretools.vscode-docker
                exiasr.hadolint

                # Nix
                jnoortheen.nix-ide
                #kamadorueda.alejandra

                # devenv: mirror the devenv environment into the editor and terminals
                datakurre.devenv

                # MD
                shd101wyy.markdown-preview-enhanced
                yzhang.markdown-all-in-one
                davidanson.vscode-markdownlint

                # MDX
                unifiedjs.vscode-mdx

                # Typst
                myriad-dreamin.tinymist

                # HTML/VSS/JS/TS
                bradlc.vscode-tailwindcss
                dbaeumer.vscode-eslint
                ecmel.vscode-html-css
                esbenp.prettier-vscode
                astro-build.astro-vscode

                # AI
                fedaykindev.openchamber # openchamber.apiUrl

                # Rest
                #humao.rest-client

                # HCL
                hashicorp.hcl
              ]
              ++ [
                vscode-ltex-plus-offline # https://ltex-plus.github.io/ltex-plus/advanced-usage.html
              ];

            # Enable these 2 to prevent homeManager's userSettings from being written
            enableUpdateCheck = true;
            enableExtensionUpdateCheck = true;
          };

          # userSettings = lib.importJSON ./settings.json; # Using home.mutableFile instead
        };

        stylix.targets.vscode.enable = false; # We are using the one from extension

        home.mutableFile = {
          # code --diff users/krumpy-miha/home/ide/settings.json ~/.config/VSCodium/User/settings.json
          ".config/VSCodium/User/settings.json".source = ./vscode-settings.jsonc;
          ".vscode-oss/argv.json".source = ./vscode-argv.jsonc;
        };
      };
  };
}

{
  config,
  osConfig,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.home.mutableFile;

  backupExt = osConfig.home-manager.backupFileExtension or "backup";

  mkSource = file:
    if file.text != null
    then pkgs.writeText "mutable-file" file.text
    else file.source;
in {
  options.home.mutableFile = mkOption {
    description = "Mutable files to manage in home directory.";
    default = {};

    type = types.attrsOf (types.submodule ({name, ...}: {
      options = {
        enable = mkEnableOption "mutable file" // {default = true;};

        target = mkOption {
          type = types.str;
          default = name;
          description = "Path to target file relative to home directory.";
        };

        text = mkOption {
          type = types.nullOr types.lines;
          default = null;
          description = "Text content of the file.";
        };

        source = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Source file path.";
        };

        mode = mkOption {
          type = types.str;
          default = "0600";
          description = "File permissions (octal).";
        };
      };
    }));
  };

  config = {
    assertions = flatten (mapAttrsToList (name: file: [
        {
          assertion = !(file.text != null && file.source != null);
          message = "home.mutableFile.${name}: cannot set both 'text' and 'source'";
        }
      ])
      cfg);

    home.activation.mutableFiles = lib.hm.dag.entryAfter ["writeBoundary"] ''
      echo "Checking mutable files..."
      backupExt="${backupExt}"

      updateFile() {
        local src="$1" target="$2" mode="$3"
        local dir="$(dirname "$target")"
        local backup="$target.$backupExt"

        $DRY_RUN_CMD mkdir -p "$dir"

        if [ -f "$backup" ]; then
          echo "Removing backup: $backup"
          $DRY_RUN_CMD rm -f "$backup"
        fi

        if [ ! -f "$target" ] || ! cmp -s "$src" "$target" || [ "$(stat -c %a "$target")" != "$mode" ]; then
          $DRY_RUN_CMD install -m "$mode" $VERBOSE_ARG "$src" "$target"
          echo "Updated: $target"
        else
          echo "Up to date: $target"
        fi
      }

      ${concatStringsSep "\n" (mapAttrsToList (_: file: ''
        updateFile "${mkSource file}" "$HOME/${escapeShellArg file.target}" "${file.mode}"
      '') (filterAttrs (_: f: f.enable) cfg))}
    '';
  };
}

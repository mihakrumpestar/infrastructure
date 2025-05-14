{
  config,
  osConfig,
  lib,
  pkgs,
  ...
}:
with lib; let
  mutableFileOpts = {name, ...}: {
    options = {
      enable =
        mkEnableOption "this mutable file"
        // {
          default = true;
        };

      target = mkOption {
        type = types.str;
        default = name;
        description = "Path to target file relative to user's home directory.";
      };

      text = mkOption {
        type = types.nullOr types.lines;
        default = null;
        description = "Text content of the file.";
      };

      source = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path of the source file.";
      };

      mode = mkOption {
        type = types.str;
        default = "0600";
        description = "Permissions mode for the file (in octal string format).";
      };
    };

    config = {
      target = mkDefault name;
    };
  };

  mkSourceDerivation = name: file:
    if file.text != null
    then pkgs.writeText "mutable-file-${name}" file.text
    else
      pkgs.runCommand "mutable-file-source-${name}" {} ''
        mkdir -p $out
        cp ${file.source} $out/${baseNameOf file.source}
      '';
in {
  options.my = {
    home.mutableFile = mkOption {
      type = types.attrsOf (types.submodule mutableFileOpts);
      default = {};
      description = "Attribute set of mutable files to manage.";
    };
  };

  config = {
    home.activation.mutableFiles = lib.hm.dag.entryAfter ["writeBoundary"] ''
      echo "Checking mutable files..."

      backupExt="${osConfig.home-manager.backupFileExtension}"

      updateMutableFile() {
        local source="$1"
        local target="$2"
        local mode="$3"
        local dir="$(dirname "$target")"
        local backup="$target.$backupExt"

        $DRY_RUN_CMD mkdir -p "$dir"

        # Remove the backup file if it exists
        if [ -f "$backup" ]; then
          echo "Removing backup file: $backup"
          $DRY_RUN_CMD rm -f "$backup"
        fi

        if [ ! -f "$target" ] || ! cmp -s "$source" "$target" || [ "$(stat -c %a "$target")" != "$mode" ]; then
          $DRY_RUN_CMD install -m "$mode" $VERBOSE_ARG "$source" "$target"
          echo "Updated mutable file: $target"
        else
          echo "Mutable file is up to date: $target"
        fi
      }

      ${concatStringsSep "\n" (
        mapAttrsToList (
          name: file:
            optionalString file.enable (
              let
                sourceDrv = mkSourceDerivation name file;
                sourceFile =
                  if file.text != null
                  then sourceDrv
                  else "${sourceDrv}/${baseNameOf file.source}";
              in ''
                updateMutableFile ${escapeShellArg sourceFile} \
                  "$HOME/${escapeShellArg file.target}" \
                  ${escapeShellArg file.mode}
              ''
            )
        )
        config.my.home.mutableFile
      )}
    '';
  };
}

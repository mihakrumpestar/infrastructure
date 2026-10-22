{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.remmina-config-gen;

  credentials = import ./credentials.nix { inherit config lib pkgs; };

  inherit (credentials)
    mkOptions
    hasCredential
    systemdPath
    credentialArgs
    ;

  tool = pkgs.callPackage ../package.nix { subPackage = "remmina-config-gen"; };

  databasePath = systemdPath cfg.database;

  # Watch the containing directory too: KeePassXC saves atomically (temp file +
  # rename), and PathChanged on the file alone does not reliably fire on a
  # rename-in (systemd issues #20934, #17727, #31941).
  databaseDir = builtins.dirOf databasePath;

  # The tool reads remmina.pref only to discover Remmina's datadir.
  remminaPref = "%h/.config/remmina/remmina.pref";

  args = [
    "--database ${lib.escapeShellArg cfg.database}"
    "--keepassxc-cli ${lib.escapeShellArg cfg.keepassxcCli}"
    # Skip (without reading the DB) when the file is unchanged, so unrelated
    # directory events never trigger re-authentication.
    "--if-changed"
  ]
  ++ lib.optional (cfg.outputDir != null) "--output-dir ${lib.escapeShellArg cfg.outputDir}"
  ++ [ "--prefix ${lib.escapeShellArg cfg.prefix}" ]
  ++ credentialArgs cfg;
in
{
  options.programs.remmina-config-gen = mkOptions // {
    enable = lib.mkEnableOption "KeePassXC-driven Remmina profile generation";

    package = lib.mkOption {
      type = lib.types.package;
      default = tool;
      defaultText = lib.literalExpression ''pkgs.callPackage ../package.nix { subPackage = "remmina-config-gen"; }'';
      description = "The remmina-config-gen package to use.";
    };

    outputDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Directory for generated Remmina profiles. When null, the tool auto-detects Remmina's datadir from remmina.pref.";
    };

    prefix = lib.mkOption {
      type = lib.types.str;
      default = "keepass_";
      description = "Filename prefix for generated Remmina profiles.";
    };

    service = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Install the on-demand regeneration service; it is never started at
          login. Trigger it with service.watch or `systemctl --user start
          remmina-config-gen`. The tray regenerates directly.
        '';
      };

      watch = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Regenerate whenever the KeePassXC database or remmina.pref changes
          (systemd path unit). A run may still prompt; off by default, prefer the
          tray for intentional refreshes.
        '';
      };
    };

    tray = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Run a system tray icon (StatusNotifierItem) with Refresh, Open profiles, Show log, and Quit actions.";
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        home.packages = [
          cfg.package
          pkgs.keepassxc
        ];
      }

      (lib.mkIf (cfg.service.enable && hasCredential cfg) (
        lib.mkMerge [
          {
            # Never enabled at default.target: a run may need an interactive or
            # hardware unlock. The generated profiles persist until an explicit
            # refresh or a real database change.
            systemd.user.services.remmina-config-gen = {
              Unit = {
                Description = "Generate Remmina profiles from KeePassXC";
              };
              Service = {
                Type = "oneshot";
                # Debounce: the directory watch can fire several events per save.
                ExecStartPre = "${pkgs.coreutils}/bin/sleep 1";
                ExecStart = lib.concatStringsSep " " ([ "${cfg.package}/bin/remmina-config-gen" ] ++ args);
              };
            };
          }

          (lib.mkIf cfg.service.watch {
            systemd.user.paths.remmina-config-gen = {
              Unit = {
                Description = "Watch the KeePassXC database and remmina.pref for changes";
              };
              Path = {
                PathChanged = [
                  databasePath
                  databaseDir
                  remminaPref
                ];
              };
              Install.WantedBy = [ "default.target" ];
            };
          })
        ]
      ))

      (lib.mkIf (cfg.tray.enable && hasCredential cfg) {
        systemd.user.services.remmina-config-gen-tray = {
          Unit = {
            Description = "remmina-config-gen tray";
            PartOf = [ "graphical-session.target" ];
            After = [ "graphical-session.target" ];
          };
          Service = {
            Type = "simple";
            ExecStart = lib.concatStringsSep " " (
              [
                "${cfg.package}/bin/remmina-config-gen"
                "--tray"
              ]
              ++ args
            );
            Restart = "on-failure";
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };
      })
    ]
  );
}

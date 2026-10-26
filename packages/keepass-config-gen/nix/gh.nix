{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.gh-config-gen;

  tool = pkgs.callPackage ../package.nix { subPackage = "gh-config-gen"; };

  # systemd does not expand ~ in unit arguments; use %h for the user's home.
  absolutePath =
    path:
    if lib.hasPrefix "~/" path then
      "${config.home.homeDirectory}/${lib.removePrefix "~/" path}"
    else
      path;

  args = [
    "--output ${lib.escapeShellArg cfg.output}"
  ];

  unitName = "gh-config-gen";
  trayUnitName = "gh-config-gen-tray";
  timerUnitName = "gh-config-gen";
in
{
  options.programs.gh-config-gen = {
    enable = lib.mkEnableOption "reconciling the gh CLI hosts file with the Secret Service";

    package = lib.mkOption {
      type = lib.types.package;
      default = tool;
      defaultText = lib.literalExpression ''pkgs.callPackage ../package.nix { subPackage = "gh-config-gen"; }'';
      description = "The gh-config-gen package to use.";
    };

    output = lib.mkOption {
      type = lib.types.str;
      default = "~/.config/gh/hosts.yml";
      description = ''
        gh hosts file to reconcile. It must stay writable: a store symlink or a
        read-only file makes every run fail.
      '';
    };

    service = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install the reconciliation service and its timer.";
      };

      interval = lib.mkOption {
        type = lib.types.str;
        default = "15min";
        description = ''
          How often to reconcile. A run is one metadata-only D-Bus query, so
          polling is nearly free, and it is the only way to notice that
          KeePassXC has just published a newly synced or newly unlocked
          account. KeePassXC exposes no unlock signal.
        '';
      };

      tray = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Run a system tray icon (StatusNotifierItem) with Refresh, Open config, Show log, and Quit actions.";
        };
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            # programs.gh.hosts generates its own read-only store symlink, so
            # the two would fight over the same path.
            assertion = config.programs.gh.hosts == { };
            message = "programs.gh-config-gen.output and programs.gh.hosts both manage the gh hosts file; keep programs.gh.hosts empty";
          }
        ];

        home.packages = [ cfg.package ];

        # The tool owns this file. A symlink left behind by an earlier
        # generation (or by programs.gh) would make every write fail.
        home.activation.ghConfigGenOutput = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          if [[ -L ${lib.escapeShellArg (absolutePath cfg.output)} ]]; then
            run rm --force ${lib.escapeShellArg (absolutePath cfg.output)}
          fi
        '';
      }

      (lib.mkIf cfg.service.enable {
        systemd.user.services.${unitName} = {
          Unit = {
            Description = "Reconcile gh accounts with the Secret Service";
          };
          Service = {
            Type = "oneshot";
            # A locked or absent keyring is a warning, never an unlock, so this
            # cannot prompt. Never restart into a tight loop either: the timer
            # is the retry mechanism.
            ExecStart = lib.concatStringsSep " " ([ "${cfg.package}/bin/gh-config-gen" ] ++ args);
          };
        };

        systemd.user.timers.${timerUnitName} = {
          Unit = {
            Description = "Reconcile gh accounts with the Secret Service";
            PartOf = [ "graphical-session.target" ];
          };
          Timer = {
            # A start two minutes into the session is enough for KeePassXC to
            # have been autostarted, and keeps every later tick cheap.
            OnStartupSec = "2min";
            OnUnitActiveSec = cfg.service.interval;
            AccuracySec = "1min";
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };
      })

      (lib.mkIf (cfg.service.enable && cfg.service.tray.enable) {
        systemd.user.services.${trayUnitName} = {
          Unit = {
            Description = "gh-config-gen tray";
            PartOf = [ "graphical-session.target" ];
            After = [ "graphical-session.target" ];
          };
          Service = {
            Type = "simple";
            ExecStart = lib.concatStringsSep " " (
              [
                "${cfg.package}/bin/gh-config-gen"
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

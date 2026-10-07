{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.ssh-config-gen;

  tool = pkgs.callPackage ./package.nix { };

  # Unattended regeneration (the systemd service) needs a credential that does
  # not require a terminal.
  # A key file or YubiKey is not sufficient on its own: the database may also
  # require a master password. Unattended unlock needs either an explicit
  # password source or a declaration that no password is required.
  hasCredential = cfg.noPassword || cfg.passwordCommand != null || cfg.passwordFile != null;

  # systemd path units do not expand ~; use %h for the user's home.
  systemdPath = path: if lib.hasPrefix "~/" path then "%h/${lib.removePrefix "~/" path}" else path;

  # git wants an absolute path for allowedSignersFile.
  absolutePath =
    path:
    if lib.hasPrefix "~/" path then
      "${config.home.homeDirectory}/${lib.removePrefix "~/" path}"
    else
      path;

  # Empty values disable the corresponding output in the tool.
  allowedSignersArg = lib.optionalString cfg.allowedSigners.enable cfg.allowedSigners.path;
  gitIdentitiesArg = lib.optionalString cfg.git.enable cfg.git.identitiesDir;

  databasePath = systemdPath cfg.database;

  # Watch the containing directory too: KeePassXC saves atomically (temp file +
  # rename), and PathChanged on the file alone does not reliably fire on a
  # rename-in (systemd issues #20934, #17727, #31941).
  databaseDir = builtins.dirOf databasePath;

  allowedSignersPath = absolutePath cfg.allowedSigners.path;

  args = [
    "--database ${lib.escapeShellArg cfg.database}"
    "--keepassxc-cli ${lib.escapeShellArg cfg.keepassxcCli}"
    "--output ${lib.escapeShellArg cfg.output}"
    "--identities-dir ${lib.escapeShellArg cfg.identitiesDir}"
    "--allowed-signers ${lib.escapeShellArg allowedSignersArg}"
    "--git-identities-dir ${lib.escapeShellArg gitIdentitiesArg}"
    # Skip (without reading the DB) when the file is unchanged, so unrelated
    # directory events never trigger re-authentication.
    "--if-changed"
  ]
  ++ lib.optional (cfg.keyfile != null) "--keyfile ${lib.escapeShellArg cfg.keyfile}"
  ++ lib.optional (cfg.yubikey != null) "--yubikey ${lib.escapeShellArg cfg.yubikey}"
  ++ lib.optional cfg.noPassword "--no-password"
  ++ lib.optional (
    cfg.passwordCommand != null
  ) "--password-command ${lib.escapeShellArg cfg.passwordCommand}"
  ++ lib.optional (cfg.passwordFile != null) "--password-file ${lib.escapeShellArg cfg.passwordFile}"
  ++ lib.optional (cfg.agentSocket != null) "--agent-socket ${lib.escapeShellArg cfg.agentSocket}";
in
{
  options.programs.ssh-config-gen = {
    enable = lib.mkEnableOption "KeePassXC-driven ssh config generation";

    package = lib.mkOption {
      type = lib.types.package;
      default = tool;
      defaultText = lib.literalExpression "pkgs.callPackage ./package.nix { }";
      description = "The ssh-config-gen package to use.";
    };

    database = lib.mkOption {
      type = lib.types.str;
      default = "~/Passwords.kdbx";
      description = "KeePassXC .kdbx database to read.";
    };

    keepassxcCli = lib.mkOption {
      type = lib.types.str;
      default = "${pkgs.keepassxc}/bin/keepassxc-cli";
      defaultText = lib.literalExpression "\${pkgs.keepassxc}/bin/keepassxc-cli";
      description = "keepassxc-cli binary used to read the database.";
    };

    output = lib.mkOption {
      type = lib.types.str;
      default = "~/.ssh/config.d/keepass.conf";
      description = "Generated ssh config fragment.";
    };

    identitiesDir = lib.mkOption {
      type = lib.types.str;
      default = "~/.ssh/keepass-identities";
      description = "Directory for public keys derived from the database. Separate from the Nix-managed ~/.ssh/identities to avoid collisions.";
    };

    allowedSigners = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Generate an allowed_signers file for SSH commit signing.";
      };

      path = lib.mkOption {
        type = lib.types.str;
        default = "~/.ssh/allowed_signers";
        description = "Path to the generated allowed_signers file.";
      };
    };

    git = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Point git at the generated allowed_signers file, enable SSH signing,
          and generate per-line git identity files (from ssh_hosts lines that
          carry git.name/git.email). Also generates
          ~/.config/git/keepass-identities/include.conf, which auto-applies each
          identity by remote alias. Off by default because the gpg wiring
          conflicts with any other definition of
          programs.git.settings.gpg.ssh.allowedSignersFile.
        '';
      };

      identitiesDir = lib.mkOption {
        type = lib.types.str;
        default = "~/.config/git/keepass-identities";
        description = "Directory for generated git identity files (included by the generated include.conf).";
      };
    };

    agentSocket = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional IdentityAgent socket to emit in every generated Host block.";
    };

    keyfile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "KeePassXC key file, if the database uses one.";
    };

    yubikey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "YubiKey/OnlyKey slot[:serial] for challenge-response unlocking (e.g. \"2\" or \"2:7370001\").";
    };

    noPassword = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Set when the database has no master password (challenge-response/key-file only).";
    };

    passwordCommand = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Command that prints the database master password.";
    };

    passwordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "File containing the database master password.";
    };

    includeInSshConfig = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Add the generated fragment to programs.ssh.includes.";
    };

    service = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Install the on-demand regeneration service; it is never started at
          login. Trigger it with service.watch or `systemctl --user start
          ssh-config-gen`. The tray regenerates directly.
        '';
      };

      watch = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Regenerate whenever the KeePassXC database changes (systemd path unit).
          A run may still prompt; off by default, prefer the tray for intentional
          refreshes.
        '';
      };
    };

    tray = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Run a system tray icon (StatusNotifierItem) with Refresh, Open config, and Quit actions.";
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

        # Glob (not the literal file) so a not-yet-generated fragment is silent
        # rather than an ssh "Can't open ..." error.
        programs.ssh.includes = lib.mkIf cfg.includeInSshConfig [
          "${dirOf cfg.output}/*.conf"
        ];
      }

      (lib.mkIf (cfg.git.enable && cfg.allowedSigners.enable) {
        programs.git.settings.gpg = {
          format = "ssh";
          ssh.allowedSignersFile = allowedSignersPath;
        };
      })

      (lib.mkIf cfg.git.enable {
        programs.git.settings.include.path = "${cfg.git.identitiesDir}/include.conf";
      })

      (lib.mkIf (cfg.service.enable && hasCredential) (
        lib.mkMerge [
          {
            # Deliberately never enabled at default.target. A run may need an
            # interactive/hardware unlock (e.g. a touch-requiring YubiKey
            # challenge-response). Were the unit wanted by default.target it
            # would be started on every user-manager start and on every
            # NixOS/home-manager activation (sd-switch starts units that are
            # "WantedByActiveTarget" and not currently active), prompting at the
            # worst possible time. The generated config persists until it is
            # refreshed, so there is no reason to regenerate at start: only an
            # explicit refresh or a real database change should trigger a run.
            systemd.user.services.ssh-config-gen = {
              Unit = {
                Description = "Generate ssh config from KeePassXC";
              };
              Service = {
                Type = "oneshot";
                # Debounce: the directory watch can fire several events per save.
                ExecStartPre = "${pkgs.coreutils}/bin/sleep 1";
                ExecStart = lib.concatStringsSep " " ([ "${cfg.package}/bin/ssh-config-gen" ] ++ args);
              };
            };
          }

          (lib.mkIf cfg.service.watch {
            systemd.user.paths.ssh-config-gen = {
              Unit = {
                Description = "Watch the KeePassXC database for changes";
              };
              Path = {
                PathChanged = [
                  databasePath
                  databaseDir
                ];
              };
              Install.WantedBy = [ "default.target" ];
            };
          })
        ]
      ))

      (lib.mkIf (cfg.tray.enable && hasCredential) {
        systemd.user.services.ssh-config-gen-tray = {
          Unit = {
            Description = "ssh-config-gen tray";
            PartOf = [ "graphical-session.target" ];
            After = [ "graphical-session.target" ];
          };
          Service = {
            Type = "simple";
            ExecStart = lib.concatStringsSep " " (
              [
                "${cfg.package}/bin/ssh-config-gen"
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

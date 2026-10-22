{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Unattended regeneration (the systemd service) needs a credential that does
  # not require a terminal.
  # A key file or YubiKey is not sufficient on its own: the database may also
  # require a master password. Unattended unlock needs either an explicit
  # password source or a declaration that no password is required.
  hasCredential = cfg: cfg.noPassword || cfg.passwordCommand != null || cfg.passwordFile != null;

  # systemd path units do not expand ~; use %h for the user's home.
  systemdPath = path: if lib.hasPrefix "~/" path then "%h/${lib.removePrefix "~/" path}" else path;

  # git wants an absolute path for allowedSignersFile.
  absolutePath =
    path:
    if lib.hasPrefix "~/" path then
      "${config.home.homeDirectory}/${lib.removePrefix "~/" path}"
    else
      path;

  # Shared database and credential options for every generator module.
  mkOptions = {
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
  };

  # CLI flags corresponding to the shared credential options.
  credentialArgs =
    cfg:
    lib.optional (cfg.keyfile != null) "--keyfile ${lib.escapeShellArg cfg.keyfile}"
    ++ lib.optional (cfg.yubikey != null) "--yubikey ${lib.escapeShellArg cfg.yubikey}"
    ++ lib.optional cfg.noPassword "--no-password"
    ++ lib.optional (
      cfg.passwordCommand != null
    ) "--password-command ${lib.escapeShellArg cfg.passwordCommand}"
    ++ lib.optional (cfg.passwordFile != null) "--password-file ${lib.escapeShellArg cfg.passwordFile}";
in
{
  inherit
    mkOptions
    hasCredential
    systemdPath
    absolutePath
    credentialArgs
    ;
}

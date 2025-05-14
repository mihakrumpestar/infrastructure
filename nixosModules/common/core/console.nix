{
  config = {
    # Locale
    i18n = {
      defaultLocale = "en_US.UTF-8";
      extraLocaleSettings = {
        LC_ADDRESS = "sl_SI.UTF-8";
        LC_IDENTIFICATION = "sl_SI.UTF-8";
        LC_MEASUREMENT = "sl_SI.UTF-8";
        LC_MONETARY = "sl_SI.UTF-8";
        LC_NAME = "sl_SI.UTF-8";
        LC_NUMERIC = "sl_SI.UTF-8";
        LC_PAPER = "sl_SI.UTF-8";
        LC_TELEPHONE = "sl_SI.UTF-8";
        LC_TIME = "sl_SI.UTF-8";
      };
    };

    console = {
      earlySetup = true;
      keyMap = "slovene";
    };

    # nano fix
    programs.nano.nanorc = ''
      unset mouse # Disable mouse support
    '';
  };
}

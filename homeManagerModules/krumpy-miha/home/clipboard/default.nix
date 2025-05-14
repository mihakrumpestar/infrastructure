{pkgs, ...}: {
  services.copyq.enable = true;

  home.packages = with pkgs; [
    wl-clipboard # Dep for above

    ydotool
    grim
    slurp
  ];

  # TODO: https://copyq.readthedocs.io/en/latest/faq.html#why-does-pasting-from-copyq-not-work

  my.home.mutableFile.".config/copyq/copyq-commands.ini".source = ./copyq-commands.ini;
}

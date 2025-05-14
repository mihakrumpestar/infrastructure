{...}: {
  imports = [
    ./plasma
  ];

  # GNOME and GTK fix
  programs.dconf.enable = true;
}

{
  my.users."krumpy-miha".enable = true;

  home-manager.users."krumpy-miha" = {
    my.home = {
      fullAutostart.enable = true;
      backup.enable = true;
      dead-mens-switch.enable = true;
    };
  };
}

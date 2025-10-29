{osConfig, ...}: {
  home.stateVersion = osConfig.system.nixos.release;

  systemd.user.startServices = "sd-switch";

  programs.zsh.enable = true; # Uses nix config # TODO: extend with ZSH history
}

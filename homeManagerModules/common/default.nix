{osConfig, ...}: {
  imports = [
    ./mutable-file.nix
    ./sops-secrets.nix
    ./store-secrets.nix
  ];

  home.stateVersion = osConfig.system.nixos.release;

  systemd.user.startServices = "sd-switch";

  programs.zsh.enable = true; # Uses nix config # TODO: extend with ZSH history
}

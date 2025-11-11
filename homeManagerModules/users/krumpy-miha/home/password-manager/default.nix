{pkgs, ...}: {
  #imports = [
  #  ./onlykey-app
  #];

  home.packages = with pkgs; [
    keepassxc
    #onlykey # Does not work, using custom one
    onlykey-cli
    openssh # ssh-agent
    kdePackages.ksshaskpass
    libsecret # secret-tool

    bitwarden-desktop
    bitwarden-cli

    docker-credential-helpers # Adds secretservice to docker login
  ];

  my.home.mutableFile.".config/keepassxc/keepassxc.ini".source = ./keepassxc.ini;

  # TODO: podman
  home.file.".docker/config.json".text = ''
    {
      "credsStore": "secretservice"
    }
  '';
}

{ ... }:
{
  home.password-manager = {
    homeManager =
      { pkgs, ... }:
      {
        home.packages = with pkgs; [
          keepassxc
          onlykey
          onlykey-cli
          openssh # ssh-agent
          kdePackages.ksshaskpass
          libsecret # secret-tool
          docker-credential-helpers # Adds secretservice to docker login
        ];

        home.mutableFile.".config/keepassxc/keepassxc.ini".source = ./keepassxc.ini;

        # TODO: podman
        home.file.".docker/config.json".text = ''
          {
            "credsStore": "secretservice"
          }
        '';
      };
  };
}

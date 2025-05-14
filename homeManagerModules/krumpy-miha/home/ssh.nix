{
  config,
  lib,
  ...
}: let
  sshI = config.my.store-secrets.secrets.ssh.identities;
  sshU = config.my.store-secrets.secrets.ssh.users;
in {
  home = {
    file = {
      ".ssh/identitiesS/home_pc.pub".text = sshI.home.pc;
      ".ssh/identitiesS/homelab_servers.pub".text = sshI.homelab.servers;
      ".ssh/identitiesS/homelab_vms.pub".text = sshI.homelab.vms;
      ".ssh/identitiesS/company_01_server_01.pub".text = sshI.company_01.server_01;

      # Git
      ".ssh/identitiesS/personal.pub".text = sshI.git.personal;
      ".ssh/identitiesS/fri.pub".text = sshI.git.fri;
    };

    activation.sshIdentities = lib.hm.dag.entryAfter ["writeBoundary"] ''
      echo "Fixing ssh identities..."

      chmod -R 0777 ~/.ssh/identities || true
      rm -rf ~/.ssh/identities
      cp -f -R -L -T ~/.ssh/identitiesS ~/.ssh/identities
      chown -R ${config.home.username} ~/.ssh/identities
      chmod 0500 ~/.ssh/identities
      chmod -R 0400 ~/.ssh/identities/*

      echo "Fixed ssh identities..."
    '';
  };

  programs.ssh = {
    enable = true;
    matchBlocks = {
      "local" = {
        hostname = "localhost";
        user = "root";
        port = 22222;
        #identityFile = "~/.ssh/identities/home_pc.pub";
        #identitiesOnly = true;
      };

      "personal-workstation" = {
        hostname = "personal-workstation";
        user = "root";
        port = 22222;
        identityFile = "~/.ssh/identities/home_pc.pub";
        identitiesOnly = true;
      };

      "company_01_server_01" = {
        hostname = "company_01_server_01";
        user = "automations";
        identityFile = "~/.ssh/identities/company_01_server_01.pub";
        identitiesOnly = true;
      };

      "personal_vps_01" = {
        hostname = "personal_vps_01";
        user = "root";
        identityFile = "~/.ssh/identities/homelab_vms.pub";
        identitiesOnly = true;
      };

      "pve-01" = {
        hostname = "pve-01";
        user = "root";
        identityFile = "~/.ssh/identities/homelab_servers.pub";
        identitiesOnly = true;
      };

      "server-03" = {
        hostname = "server-03";
        user = "root";
        port = 22222;
        identityFile = "~/.ssh/identities/homelab_servers.pub";
        identitiesOnly = true;
      };

      "docker-swarm" = {
        hostname = "docker-swarm";
        user = "admin";
        port = 22222;
        identityFile = "~/.ssh/identities/homelab_vms.pub";
        identitiesOnly = true;
      };

      "orange-pi-pc" = {
        hostname = "orange-pi-pc";
        user = "admin";
        identityFile = "~/.ssh/identities/homelab_vms.pub";
        identitiesOnly = true;
      };

      "github_personal" = {
        hostname = "github.com";
        user = sshU.personal.email;
        identityFile = "~/.ssh/identities/personal.pub";
        identitiesOnly = true;
      };

      "github_fri" = {
        hostname = "github.com";
        user = sshU.fri.email;
        identityFile = "~/.ssh/identities/fri.pub";
        identitiesOnly = true;
      };
    };
  };

  home.file.".docker/config.json".text = ''
    {
      "credsStore": "secretservice"
    }
  '';
}

{ ... }:
{
  home.ssh = {
    homeManager =
      { ... }:
      {
        # Base SSH client config only. Host blocks are generated from
        # KeePassXC by ssh-config-gen (see programs.ssh-config-gen).
        programs.ssh = {
          enable = true;
          enableDefaultConfig = false;
          settings = {
            local = {
              HostName = "localhost";
              User = "root";
              Port = 22222;
            };

            # Redirect ssh to github https since company firewalls usually block port 22.
            "github.com" = {
              HostName = "ssh.github.com";
              Port = 443;
              User = "git";
            };

            "*" = {
              # Only offer the identities declared for a host. Hosts without a
              # generated IdentityFile (i.e. not in KeePassXC) are offered no
              # keys at all and fall back to password/keyboard-interactive.
              IdentitiesOnly = true;
              ForwardAgent = false;
              AddKeysToAgent = "no";
              Compression = false;
              ServerAliveInterval = 0;
              ServerAliveCountMax = 3;
              HashKnownHosts = false;
              UserKnownHostsFile = "~/.ssh/known_hosts";
              ControlMaster = "no";
              ControlPath = "~/.ssh/master-%r@%n:%p";
              ControlPersist = "no";
            };
          };
        };
      };
  };
}

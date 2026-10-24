{ ... }:
{
  # Local, non-declarative dev DNS.
  #
  # dnsmasq is the app-facing resolver: it answers address=/<domain>/<ip>
  # overrides and forwards everything else to the systemd-resolved stub, so
  # per-link DHCP and NetBird split DNS still work.
  #
  # Edit /var/lib/dev-dns/addresses.conf:
  #   address=/infra.example.com/127.0.0.1
  #   address=/vm.internal/10.0.0.42
  #
  # A path unit validates and restarts dnsmasq on change.
  # dnsmasq 2.86+ forwards other record types for address= domains; add
  # local=/<domain>/ to stop AAAA leaking. DoH clients and `resolvectl query`
  # bypass these overrides; verify with `getent hosts` or `dig`.
  den.aspects.dev-dns = {
    nixos =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      with lib;
      let
        cfg = config.my.devDns;
        addressDir = dirOf cfg.addressFile;
        seedFile = pkgs.writeText "dev-dns-seed.conf" cfg.seed;
        # resolved stub: dnsmasq upstream and NetBird DNS-manager signal.
        resolvedStub = "127.0.0.53";
      in
      {
        options.my.devDns = {
          listenAddress = mkOption {
            type = types.str;
            default = "127.0.0.1";
            description = ''
              Loopback address dnsmasq binds on port 53 (resolv.conf cannot
              express a port). Must not be resolved's 127.0.0.53/54.
            '';
          };

          addressFile = mkOption {
            type = types.str;
            default = "/var/lib/dev-dns/addresses.conf";
            description = ''
              Mutable dnsmasq snippet holding the `address=/<domain>/<ip>`
              entries. Seeded once and never overwritten.
            '';
          };

          autoApply = mkOption {
            type = types.bool;
            default = true;
            description = "Restart dnsmasq automatically when the address file changes.";
          };

          seed = mkOption {
            type = types.lines;
            default = ''
              # address=/<domain>/<ip> resolves the domain and all subdomains.
              # address=/app.example.com/127.0.0.1
              # Add local=/<domain>/ to stop other record types leaking upstream.
            '';
            description = "Initial contents of the address file, written only if it does not exist.";
          };
        };

        config = {
          assertions = [
            {
              assertion = hasPrefix "/" cfg.addressFile;
              message = "my.devDns.addressFile must be an absolute path, got \"${cfg.addressFile}\"";
            }
            {
              assertion = cfg.listenAddress != resolvedStub;
              message = "my.devDns.listenAddress must not be ${resolvedStub}: dnsmasq forwards non-overridden queries to the systemd-resolved stub on that address.";
            }
            {
              assertion = config.services.resolved.enable;
              message = "my.devDns requires systemd-resolved: dnsmasq forwards non-overridden queries to its stub at ${resolvedStub}.";
            }
          ];

          # Wildcard resolver in front of everything. no-resolv plus the
          # resolved stub upstream avoids a loop and keeps per-link and
          # NetBird split DNS intact.
          services.dnsmasq = {
            enable = true;
            resolveLocalQueries = false; # true would add 127.0.0.1 as an upstream (loop)
            settings = {
              listen-address = cfg.listenAddress;
              bind-interfaces = true;
              no-resolv = true;
              server = [ resolvedStub ];
              conf-dir = "${addressDir},*.conf";
              local-ttl = 30;
            };
          };

          # dnsmasq first (resolv.conf cannot express port 53).
          # The stub must stay listed: NetBird only selects its systemd-resolved
          # backend when the stub is in resolv.conf or nss-resolve precedes dns.
          # Otherwise it tries to rewrite this read-only file, so peer DNS dies.
          environment.etc."resolv.conf".source = mkForce (
            pkgs.writeText "resolv.conf" ''
              nameserver ${cfg.listenAddress}
              nameserver ${resolvedStub}
            ''
          );

          # glibc must hit dnsmasq, not nss-resolve, so put dns first.
          system.nssDatabases.hosts = mkForce [
            "files"
            "mymachines"
            "mdns4_minimal [NOTFOUND=return]"
            "dns"
            "resolve [!UNAVAIL=return]"
            "myhostname"
          ];

          # Seed the mutable, non-store address file once. `C` never overwrites.
          systemd.tmpfiles.rules = [
            "d ${addressDir} 0755 root root -"
            "C ${cfg.addressFile} 0644 root root - ${seedFile}"
          ];

          # dnsmasq --test fails on a missing conf-dir; create it first.
          systemd.services.dnsmasq = {
            preStart = mkBefore "mkdir -p ${addressDir}";
            after = [ "systemd-tmpfiles-setup.service" ];
          };

          # Validate before restarting: a typo must not take DNS down.
          systemd.services.dev-dns-apply = mkIf cfg.autoApply {
            description = "Validate and restart dnsmasq after a dev-dns address change";
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${pkgs.writeShellScript "dev-dns-apply" ''
                set -e
                ${config.services.dnsmasq.package}/bin/dnsmasq --test -C ${config.services.dnsmasq.configFile}
                ${config.systemd.package}/bin/systemctl restart dnsmasq.service
              ''}";
            };
          };
          systemd.paths.dev-dns-apply = mkIf cfg.autoApply {
            wantedBy = [ "multi-user.target" ];
            pathConfig = {
              PathChanged = cfg.addressFile;
              Unit = "dev-dns-apply.service";
            };
          };
        };
      };
  };
}

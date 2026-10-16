{ ... }:
{
  # Local, non-declarative dev DNS for quick iteration.
  #
  # dnsmasq sits in front of the app-facing resolver: glibc apps query it
  # first, it answers any `address=/<domain>/<ip>` override (a domain and all
  # its subdomains) and forwards everything else to the systemd-resolved stub.
  # resolved still owns per-link routing, so usual DHCP DNS and NetBird
  # split DNS keep working. The only thing you edit day to day is one mutable,
  # non-store file:
  #
  #   sudo nano /var/lib/dev-dns/addresses.conf
  #
  #   address=/infra.example.com/127.0.0.1
  #   address=/vm.internal/10.0.0.42
  #
  # dnsmasq does not re-read conf-dir on SIGHUP, so a systemd path unit
  # restarts it when the file changes (validated first, so a typo cannot take
  # DNS down). Edits survive reboots because /var/lib is persisted.
  #
  # Notes:
  #  - dnsmasq 2.86+ forwards non-matching record types for an `address=`
  #    domain upstream. Add `local=/<domain>/` next to an override if you do
  #    not want AAAA/other types to leak (e.g. when overriding a real name).
  #  - Apps that bypass the system resolver (browsers with DoH, `resolvectl
  #    query`, which uses the D-Bus API) will not see these overrides. Verify
  #    with `getent hosts` or `dig`.
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
      in
      {
        options.my.devDns = {
          listenAddress = mkOption {
            type = types.str;
            default = "127.0.0.1";
            description = ''
              Loopback address dnsmasq binds on port 53. Port 53 is required:
              /etc/resolv.conf cannot express a port. Pick an address other
              than 127.0.0.1 or resolved's 127.0.0.53/54 to avoid collisions.
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
              # Local dev DNS overrides. A name and every subdomain resolve to the IP.
              # Format: address=/<domain>/<ip>
              # address=/app.example.com/127.0.0.1
              # address=/vm.internal/10.0.0.42
              #
              # dnsmasq 2.86+ forwards other record types (e.g. AAAA) upstream for
              # an address= domain. Add a matching local= line to keep it local:
              # local=/app.example.com/
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
          ];

          # Wildcard-capable resolver in front of everything. It never reads
          # /etc/resolv.conf (which now points at itself) and forwards every
          # non-overridden query to the systemd-resolved stub, which keeps
          # per-link corporate and NetBird split DNS intact.
          services.dnsmasq = {
            enable = true;
            resolveLocalQueries = false; # true would add 127.0.0.1 as an upstream (loop)
            settings = {
              listen-address = cfg.listenAddress;
              bind-interfaces = true;
              no-resolv = true;
              server = [ "127.0.0.53" ];
              conf-dir = "${addressDir},*.conf";
              local-ttl = 30;
            };
          };

          # Point the app-facing resolver at dnsmasq. Port 53 is required:
          # /etc/resolv.conf cannot express a port.
          environment.etc."resolv.conf".source = mkForce (
            pkgs.writeText "resolv.conf" ''
              nameserver ${cfg.listenAddress}
            ''
          );

          # NixOS puts nss-resolve before files/dns with [!UNAVAIL=return], so
          # glibc would bypass dnsmasq. Reorder so glibc uses dns (dnsmasq)
          # first; keep the other systemd/avahi nss modules.
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

          # A missing conf-dir is fatal to dnsmasq's preStart `--test`, so create
          # it first (mkBefore) and order after tmpfiles.
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

{ den, ... }:
{
  den.aspects.nomad = {
    # Runtime dep: podman aspect. Consul integration lives in consul.nix.
    includes = [
      den.aspects.podman
    ];
    nixos =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        cfg = config.my.nomad;
        jsonFormat = pkgs.formats.json { };

        # Agent protocol ports (Nomad defaults). Single source of truth for
        # the advertise scheme and the exposed-interface firewall.
        protoPort = {
          http = 4646;
          rpc = 4647;
          serf = 4648;
        };

        # Bind+advertise scheme for every protocol. Nomad 2.0 rejects a
        # defaulted loopback advertise ("Defaulting advertise to localhost is
        # unsafe"), so the advertise side stays explicit.
        endpointScheme =
          { bind, advertise }:
          {
            addresses = {
              http = bind;
              rpc = bind;
              serf = bind;
            };
            advertise = {
              http = advertise protoPort.http;
              rpc = advertise protoPort.rpc;
              serf = advertise protoPort.serf;
            };
          };

        # Agent address scheme chosen by exposedInterfaces. Keys are disjoint
        # from the generated settings base, so the fold ranks layers purely
        # (base < scheme < extraSettings).
        # Advertise is always explicit loopback so the agent starts
        # unconditionally, regardless of any mesh/interface state.
        agentScheme = endpointScheme {
          bind = if cfg.exposedInterfaces == [ ] then "127.0.0.1" else "0.0.0.0";
          advertise = port: "127.0.0.1:${toString port}";
        };
      in
      {
        options.my.nomad = {
          # Single-agent Nomad; jobs use group network mode = "bridge".
          # https://developer.hashicorp.com/nomad/docs
          enable = lib.mkEnableOption "Nomad single-agent orchestrator (podman driver, mesh-reachable API, see my.nomad.exposedInterfaces)";

          region = lib.mkOption {
            type = lib.types.str;
            default = "global";
            description = "Nomad region name (default 'global').";
          };

          datacenter = lib.mkOption {
            type = lib.types.str;
            default = "dc1";
            description = "Nomad datacenter name (default 'dc1').";
          };

          disabledDrivers = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ "docker" ];
            description = ''
              Built-in task drivers to denylist (client option
              driver.denylist, comma-joined). Built-in drivers are
              compiled into the agent and spawn even when their runtime
              is absent, erroring against the missing daemon. Default
              follows this aspect's podman-only stance.
            '';
          };

          enableRawExec = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              Enable the built-in raw_exec task driver via its plugin block
              (plugin."raw_exec".config.enabled). raw_exec runs tasks as the
              agent user — root here, since dropPrivileges = false — with no
              filesystem, network, or cgroup isolation, so only run trusted
              job specs. A raw_exec entry in disabledDrivers
              (driver.denylist) overrides this and keeps the driver off.
            '';
          };

          extraCniDirs = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = ''
              Extra CNI plugin directories appended to
              services.nomad.settings.client.cni_path.
            '';
          };

          extraSettings = lib.mkOption {
            inherit (jsonFormat) type;
            default = { };
            description = ''
              Extra agent settings deep-merged over every generated leaf of
              /etc/nomad.json (services.nomad.settings). Recursive update:
              a list value replaces lists wholesale rather than appending
              (e.g. overriding client.cni_path must carry the full path).
              See https://developer.hashicorp.com/nomad/docs/configuration
            '';
          };

          exposedInterfaces = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ "wt0" ];
            description = ''
              Interfaces the agent is reachable on. HTTP/RPC/Serf bind
              0.0.0.0 and the firewall opens the agent ports only on these,
              keeping the agent off the public network.
              Default targets the NetBird mesh interface "wt0"
              (modules/system/default/networking.nix): when NetBird is up the
              agent is mesh-reachable, otherwise the interface stays idle and
              nothing is exposed — no wiring needed in either case, and the
              agent starts unconditionally regardless of NetBird state (it is
              ordered after the netbird client unit only).
              Set to [ ] for a loopback-only agent.
              The agent advertises loopback (single agent, no cross-node
              consumers); adding agents to the mesh later requires an
              explicit advertise override via `my.nomad.extraSettings`.
            '';
          };
        };

        config = lib.mkIf cfg.enable {
          # Packs bind-mount their state from /mnt/containers/<pack>/<group>/<task>.
          # Persist it across the impermanence wipe: the directories (and the
          # service data) must exist on every boot, because a restored system-job
          # allocation does not re-run its prestart storage hook, and the Podman
          # driver refuses a bind mount whose source is missing.
          my.impermanence.directories = [ "/mnt/containers" ];

          services.nomad = {
            enable = true;
            package = pkgs.nomad;

            # Rootful agent: rootful podman socket + CNI NET_ADMIN.
            dropPrivileges = false;

            enableDocker = false;

            extraSettingsPlugins = [ pkgs.nomad-driver-podman ];

            # nftables: iptables backend for the CNI plugins.
            extraPackages = [ pkgs.nftables ];

            # Generated settings, deep-overridden last by extraSettings
            # (agentScheme's addresses/advertise keys stay disjoint from the
            # base set, so fold order fully ranks the three layers).
            settings = lib.foldl lib.recursiveUpdate { } [
              {
                inherit (cfg) region datacenter;

                server = {
                  enabled = true;
                  bootstrap_expect = 1;
                };

                telemetry = {
                  prometheus_metrics = true; # /v1/metrics?format=prometheus
                  publish_allocation_metrics = true; # Minimum for Nomad UI to show stats
                  publish_node_metrics = true;
                };

                client = {
                  enabled = true;
                  # CNI binaries for group network mode=bridge (Nomad
                  # generates the conflist itself). Discovery is cni_path,
                  # not PATH.
                  cni_path = lib.concatStringsSep ":" ([ "${pkgs.cni-plugins}/bin" ] ++ cfg.extraCniDirs);
                }
                // lib.optionalAttrs (cfg.disabledDrivers != [ ]) {
                  options."driver.denylist" = lib.concatStringsSep "," cfg.disabledDrivers;
                };

                # Rootful podman driver on the default rootful socket. Since
                # Nomad 1.10 this block is required or the plugin is silently
                # skipped. The driver rejects unknown keys.
                # raw_exec is enabled below when enableRawExec is on.
                plugin = {
                  "nomad-driver-podman".config = {
                    extra_labels = [
                      "job_name"
                      "job_id"
                      "task_group_name"
                      "task_name"
                      "namespace"
                      "node_name"
                      "node_id"
                    ];
                    logging = {
                      driver = "journald";
                      options = {
                        tag = ''{{index .Config.Labels "com.hashicorp.nomad.namespace"}}/{{index .Config.Labels "com.hashicorp.nomad.job_name"}}/{{index .Config.Labels "com.hashicorp.nomad.task_group_name"}}/{{index .Config.Labels "com.hashicorp.nomad.task_name"}}'';
                      };
                    };
                  };
                }
                // lib.optionalAttrs cfg.enableRawExec {
                  raw_exec.config.enabled = true;
                };
              }
              agentScheme
              cfg.extraSettings
            ];
          };

          # Interface-scoped firewall for mesh exposure (empty list
          # contributes no interface). Requires the firewall from the
          # networking aspect (networking.firewall.enable).
          networking.firewall.interfaces = lib.genAttrs cfg.exposedInterfaces (_: {
            allowedTCPPorts = lib.attrValues protoPort;
            allowedUDPPorts = [ protoPort.serf ];
          });

          # Sequencing only: start after the netbird client units that own
          # the exposed interfaces. `wants` (not requires/Requires) means a
          # failed or missing netbird never blocks or fails nomad: the agent
          # starts unconditionally (advertise is loopback) and is simply
          # reachable over the mesh whenever the interface comes up.
          systemd.services.nomad =
            let
              netbirdUnits = lib.mapAttrsToList (_: client: "${client.service.name}.service") (
                lib.filterAttrs (
                  _: client: lib.elem client.interface cfg.exposedInterfaces
                ) config.services.netbird.clients
              );
            in
            {
              wants = netbirdUnits;
              after = netbirdUnits;
            };

          # Kernel modules + sysctls come from the included podman aspect.
        };
      };
  };
}

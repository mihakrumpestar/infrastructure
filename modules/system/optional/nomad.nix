{ den, ... }:
{
  den.aspects.nomad = {
    # Runtime deps: podman aspect (socket, kernel modules, sysctls) and
    # consul aspect (agent the scheduler integrates with).
    includes = [
      den.aspects.podman
      den.aspects.consul
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
      in
      {
        options.my.nomad = {
          # Single-agent Nomad with Consul service discovery. Jobs use
          # group network mode = "bridge": Nomad generates the bridge
          # CNI conflist itself and appends consul-cni automatically for
          # Connect transparent-proxy sidecars. consul-cni never talks to
          # Consul; Nomad feeds it the iptables config via CNI args.
          # https://developer.hashicorp.com/nomad/docs
          enable = lib.mkEnableOption "Nomad single-agent orchestrator (podman driver, loopback API)";

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

          extraSettings = lib.mkOption {
            inherit (jsonFormat) type;
            default = { };
            description = ''
              Extra agent settings deep-merged into /etc/nomad.json
              (services.nomad.settings). See
              https://developer.hashicorp.com/nomad/docs/configuration
            '';
          };
        };

        config = lib.mkIf cfg.enable {
          services.nomad = {
            enable = true;
            package = pkgs.nomad_2_0;

            # Rootful agent: rootful podman socket + CNI NET_ADMIN.
            dropPrivileges = false;

            enableDocker = false;

            extraSettingsPlugins = [ pkgs.nomad-driver-podman ];

            # consul-cni shells out via nsenter (util-linux); the consul
            # binary is required for Envoy sidecars.
            extraPackages = [
              pkgs.nftables
              pkgs.util-linux
              pkgs.consul
            ];

            settings = lib.recursiveUpdate {
              # Loopback-only: no mTLS/ACLs yet, so the API must stay off
              # the network. Remote access: ssh -L 4646:127.0.0.1:4646 (see
              # host config); NOMAD_ADDR cannot tunnel over SSH.
              addresses = {
                http = "127.0.0.1";
                rpc = "127.0.0.1";
                serf = "127.0.0.1";
              };

              # Nomad 2.0 refuses a defaulted loopback advertise
              # ("Defaulting advertise to localhost is unsafe").
              advertise = {
                http = "127.0.0.1:4646";
                rpc = "127.0.0.1:4647";
                serf = "127.0.0.1:4648";
              };

              inherit (cfg) region datacenter;

              server = {
                enabled = true;
                bootstrap_expect = 1;
              };

              client = {
                enabled = true;
                # CNI binaries for group network mode=bridge (Nomad generates
                # the conflist itself). Discovery is cni_path, not PATH.
                cni_path = "${pkgs.cni-plugins}/bin:${pkgs.consul-cni}/bin";
              }
              // lib.optionalAttrs (cfg.disabledDrivers != [ ]) {
                options."driver.denylist" = lib.concatStringsSep "," cfg.disabledDrivers;
              };

              # Rootful podman driver on the default rootful socket. Since
              # Nomad 1.10 this block is required or the plugin is silently
              # skipped. The config MUST stay empty: Nomad 2.0 JSON configs
              # cannot express nested plugin-config blocks (hcl v1 rejects
              # them with "unexpected keys"), and the driver defaults
              # already match (rootful socket, recover_stopped = false,
              # gc.container = true).
              plugin."nomad-driver-podman".config = { };
            } cfg.extraSettings;
          };

          # Consul may not be up when nomad starts; the agent retries
          # discovery, but explicit ordering keeps startup deterministic.
          systemd.services.nomad = {
            after = [ "consul.service" ];
            wants = [ "consul.service" ];
          };

          # Kernel modules + sysctls come from the included podman aspect.
        };
      };
  };
}

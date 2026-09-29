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
      in
      {
        options.my.nomad = {
          # Single-agent Nomad; jobs use group network mode = "bridge".
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

            # nftables: iptables backend for the CNI plugins.
            extraPackages = [ pkgs.nftables ];

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
                cni_path = lib.concatStringsSep ":" ([ "${pkgs.cni-plugins}/bin" ] ++ cfg.extraCniDirs);
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

          # Kernel modules + sysctls come from the included podman aspect.
        };
      };
  };
}

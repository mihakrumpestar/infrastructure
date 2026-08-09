{ ... }:
{
  # Note: this is currently in testing phase to see how well it holds up
  den.aspects.rke2 = {
    nixos =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        cfg = config.my.rke2;

        # TLS SANs: hostname + localhost + any user-specified extras (public IPs,
        # domain names for multi-cluster connectivity). Baked into the API server
        # certificate at first boot and cannot be changed without cert rotation.
        allTlsSans = [
          config.networking.hostName
          "127.0.0.1"
        ]
        ++ cfg.tlsSans;

        tlsSanFlags = map (san: "--tls-san=${san}") allTlsSans;

        # Enforce TLS 1.3 minimum (RKE2 defaults to TLS 1.2).
        # https://docs.rke2.io/security/hardening_guide
        hardeningFlags = [
          "--kube-apiserver-arg=tls-min-version=VersionTLS13"
        ];

        # etcd snapshots every 5 hours, retain 10, compressed.
        # https://docs.rke2.io/datastore/backup_restore
        etcdSnapshotFlags = [
          "--etcd-snapshot-schedule-cron=0 */5 * * *"
          "--etcd-snapshot-retention=10"
          "--etcd-snapshot-compress"
        ];

        # API server audit logging: 30 days retention, 10 rotating 100MB files.
        # https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/
        auditFlags = [
          "--kube-apiserver-arg=audit-log-maxage=30"
          "--kube-apiserver-arg=audit-log-maxbackup=10"
          "--kube-apiserver-arg=audit-log-maxsize=100"
          "--kube-apiserver-arg=audit-log-path=/var/lib/rancher/rke2/server/logs/audit.log"
        ];

        # Spegel: RKE2's embedded distributed OCI registry mirror (P2P image
        # sharing between nodes). Reduces external registry pulls: nodes share
        # already-pulled images directly with each other via a distributed hash
        # table on port 5001.
        # https://docs.rke2.io/install/registry_mirror
        # https://github.com/spegel-org/spegel
        registryFlags = [ "--embedded-registry" ];

        allExtraFlags =
          tlsSanFlags ++ hardeningFlags ++ etcdSnapshotFlags ++ auditFlags ++ registryFlags ++ cfg.extraFlags;

        # Static nft binary for kube-proxy. kube-proxy runs in a container with
        # its own rootfs, so it needs nft at a known path that doesn't depend on
        # NixOS's dynamic linker. The nft bundled in RKE2 containers crashes on
        # kernel 6.12+ due to a NULL parse_udata callback.
        # https://github.com/projectcalico/calico/issues/11750
        # https://github.com/NixOS/nixpkgs/issues/500465
        nftStatic = pkgs.pkgsStatic.nftables;
        nftHostPath = "/var/lib/rancher/rke2/agent/bin/nft";

        # Registries mirrored by Spegel. Each registry listed here is written to
        # registries.yaml, which tells containerd to try the embedded P2P mirror
        # before falling back to the upstream registry. Without this entry, Spegel
        # will not share images from that registry between nodes.
        # https://docs.rke2.io/install/registry_mirror#enabling-registry-mirroring
        registryMirrors = [
          "docker.io"
          "registry.k8s.io"
          "ghcr.io"
          "quay.io"
          "gcr.io"
        ];

        registriesYaml =
          "mirrors:\n" + lib.concatStringsSep "\n" (map (r: "  ${r}:") registryMirrors) + "\n";
      in
      {
        options.my.rke2 = {
          # RKE2: production-grade Kubernetes distribution.
          # https://docs.rke2.io/
          enable = lib.mkEnableOption "RKE2 Kubernetes distribution (production-grade)";

          tokenSecretFile = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = ''
              Path to the agenix-encrypted RKE2 cluster join token file.
              When set, the module declares the age secret and wires up
              services.rke2.tokenFile automatically.
              If null, RKE2 will generate a token automatically (server role only).
            '';
          };

          tlsSans = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = ''
              Extra TLS Subject Alternative Names for the Kubernetes API server
              certificate, beyond the default hostname and 127.0.0.1.
              Note: TLS SANs are baked into the certificate at first boot and cannot
              be changed without certificate rotation.
            '';
            example = [
              "10.0.0.10"
              "rke2.example.com"
            ];
          };

          extraFlags = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Extra CLI flags to pass to rke2. See: https://docs.rke2.io/reference/server_config";
          };

          nodeAddresses = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = ''
              Public IP addresses of all cluster nodes (including this node).
              Used to restrict firewall rules for internal ports.
              Public ports (80/443, 6443, 51871) are always open.
              On single-node, leave empty; internal ports are still reachable
              via 127.0.0.1 (loopback is always allowed by the NixOS firewall).
            '';
            example = [
              "192.0.2.10"
              "198.51.100.20"
            ];
          };
        };

        config = lib.mkIf cfg.enable {
          # Kernel modules, must be pre-loaded because security.lockKernelModules = true.
          boot.kernelModules = [
            "br_netfilter"
            "bridge"
            "veth"
            "iptable_filter"
            "iptable_nat"
            "iptable_mangle"
            "iptable_raw"
            "overlay"
            "nf_conntrack"
            "nf_nat"
            "nf_tables"
            "nft_compat"
            "nft_chain_nat"
            "nft_ct"
            "nft_fib"
            "nft_fib_ipv4"
            "nft_fib_ipv6"
            "nft_fib_inet"
            "xt_set"
            "ipt_rpfilter"
            "ip_set"
            "ip_set_hash_ip"
            "ip_set_hash_net"
            "ip_set_hash_ipportip"
            "ip_set_hash_ipportnet"
            "ip_set_hash_netport"
            "ip_set_hash_netiface"
            "ip_set_bitmap_ip"
            "ip_set_bitmap_port"
            "ip_set_bitmap_ipmac"
            "ip_set_list_set"
            "ip_vs"
            "ip_vs_rr"
            "ip_vs_wrr"
            "ip_vs_sh"
            "wireguard"
            # VXLAN: required by Cilium tunnel mode (default). Creates the
            # cilium_vxlan tunnel device for pod-to-pod encapsulation.
            "vxlan"
            # XFRM: required by Cilium v1.19+ route reconciler (NETLINK_XFRM socket).
            # See: https://github.com/cilium/cilium/issues/36600
            "xfrm_user"
            # Netfilter xt modules: required by kube-proxy and CNI portmap plugin.
            # All built as modules (=m) in NixOS kernel; must pre-load with
            # security.lockKernelModules = true. Missing any causes silent
            # iptables rule failures that break ClusterIP routing and hostPort.
            "xt_MASQUERADE" # SNAT masquerade (kube-proxy, CNI portmap)
            "xt_REJECT" # Reject packets (kube-proxy)
            "xt_multiport" # Multi-port matching (CNI portmap DNAT for hostPorts)
            "xt_statistic" # Random load balancing (kube-proxy)
            "xt_REDIRECT" # Redirect target (CNI portmap)
            "xt_NETMAP" # NETMAP target (CNI portmap)
            "xt_LOG" # Log target (kube-proxy)
            "xt_TCPMSS" # TCP MSS clamping (kube-proxy)
            "xt_connmark" # Connection mark matching
            "xt_CONNMARK" # Connection mark target
            "xt_state" # Legacy conntrack state matching
            "xt_tcpmss" # TCP MSS matching
          ];

          boot.kernel.sysctl = {
            "fs.inotify.max_user_instances" = 8192;
            "fs.inotify.max_user_watches" = 524288;
            "net.bridge.bridge-nf-call-iptables" = 1;
            "net.bridge.bridge-nf-call-ip6tables" = 1;
          };

          # RKE2 service configuration.
          # CNI is Cilium in VXLAN tunnel mode (RKE2 default) with WireGuard
          # encryption and Hubble observability.
          # https://docs.cilium.io/
          # https://docs.rke2.io/install/network_options#cilium
          #
          # kube-proxy stays enabled. Cilium coexists with kube-proxy; this is
          # stable and supported. Cilium handles ClusterIP load balancing via
          # eBPF at the pod level even with kubeProxyReplacement=false, while
          # kube-proxy handles host-namespace ClusterIP traffic.
          # https://github.com/cilium/cilium/issues/23837
          #
          # Disabling kube-proxy is unnecessary and finicky: RKE2 fails to remove
          # the existing kube-proxy static pod manifest when disable-kube-proxy is
          # added after initial deployment, requiring manual manifest deletion.
          # https://github.com/rancher/rke2/issues/2728
          services.rke2 = {
            enable = true;
            package = pkgs.rke2_1_36;
            cni = "cilium";
            extraFlags = allExtraFlags;
            gracefulNodeShutdown.enable = true;
          };

          age.secrets.rke2-token = lib.mkIf (cfg.tokenSecretFile != null) {
            file = cfg.tokenSecretFile;
          };
          services.rke2.tokenFile = lib.mkIf (cfg.tokenSecretFile != null) config.age.secrets.rke2-token.path;

          # Installs a static nft binary at a known path for kube-proxy's container.
          # Mounted into the kube-proxy pod via kube-proxy-extra-mount in config.yaml.
          systemd.services.rke2-nft-binary = {
            description = "Install static nft binary for RKE2 kube-proxy";
            before = [ "rke2-server.service" ];
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            script = ''
              mkdir -p $(dirname ${nftHostPath})
              cp ${nftStatic}/bin/nft ${nftHostPath}
              chmod 755 ${nftHostPath}
            '';
          };

          # Cilium HelmChartConfig.
          # https://docs.cilium.io/
          # https://docs.rke2.io/install/network_options#cilium
          #
          # Architecture:
          #   - VXLAN tunnel mode (RKE2 default): Cilium encapsulates pod traffic
          #     in VXLAN, encrypted by WireGuard. Requires no additional routing
          #     configuration, works out of the box.
          #   - kube-proxy stays enabled. Cilium coexists with kube-proxy.
          #   - Hubble: network observability (flow logs, service map, DNS/HTTP
          #     metrics) scraped by VictoriaMetrics via VMServiceScrape.
          #     https://docs.cilium.io/en/stable/observability/hubble/
          #
          # Note: Cilium always handles ClusterIP load balancing via eBPF at the
          # pod level (even with kubeProxyReplacement=false), bypassing
          # kube-proxy's iptables rules for pod-originated traffic. kube-proxy
          # still handles host-namespace ClusterIP traffic. This coexistence is
          # by design and stable.
          # https://github.com/cilium/cilium/issues/23837
          systemd.services.rke2-cilium-config = {
            description = "Write Cilium HelmChartConfig for WireGuard encryption";
            before = [ "rke2-server.service" ];
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            script = ''
              mkdir -p /var/lib/rancher/rke2/server/manifests
              cat > /var/lib/rancher/rke2/server/manifests/rke2-cilium-config.yaml << 'EOF'
              apiVersion: helm.cattle.io/v1
              kind: HelmChartConfig
              metadata:
                name: rke2-cilium
                namespace: kube-system
              spec:
                valuesContent: |-
                  encryption:
                    enabled: true
                    type: wireguard
                    nodeEncryption: true
                  hubble:
                    enabled: true
                    relay:
                      enabled: true
                    ui:
                      enabled: true
                    metrics:
                      enabled:
                        - dns
                        - drop
                        - tcp
                        - flow
                        - port-distribution
                        - icmp
                        - httpV2
                      enableOpenMetrics: true
                      serviceMonitor:
                        enabled: false
              EOF
            '';
          };

          # Firewall for multi-node operation on public internet.
          #
          # Public ports (open to all):
          #   80/443    Traefik ingress controller
          #   6443      Kubernetes API server
          #   51871/udp WireGuard (Cilium pod traffic encryption)
          #
          # Restricted ports (node IPs only):
          #   9345      RKE2 supervisor API + embedded registry mirror
          #   10250     kubelet API
          #   2379-2381 etcd peer/client (server nodes only)
          #   5001      Spegel P2P distributed hash table (image sharing)
          #
          # Forward rules: pod egress via host FORWARD chain (kube-proxy mode)
          networking.firewall =
            let
              restrictedTcpPorts =
                lib.optionals (config.services.rke2.role == "server") [
                  9345
                  10250
                  2379
                  2380
                  2381
                ]
                ++ lib.optionals (config.services.rke2.role == "agent") [
                  10250
                ]
                ++ [ 5001 ];
            in
            {
              allowedTCPPorts = [
                80
                443
                6443
              ];
              allowedUDPPorts = [
                51871
              ];

              # Allow pod egress through host FORWARD chain.
              extraForwardRules = [
                "ip saddr 10.42.0.0/16 accept"
                "ip daddr 10.42.0.0/16 accept"
              ];

              # Allow restricted ports only from specified node IPs.
              extraInputRules = lib.concatStringsSep "\n" (
                lib.flatten (
                  map (
                    port: map (ip: "ip saddr ${ip} tcp dport ${toString port} accept") cfg.nodeAddresses
                  ) restrictedTcpPorts
                )
              );
            };

          # RKE2 state that must survive reboots (impermanence).
          my.impermanence.directories = [
            "/var/lib/rancher/rke2" # Cluster state, certs, etcd data, manifests
            "/var/lib/kubelet" # Pod state, volumes, plugin data
            "/var/lib/cni" # CNI configuration and state
          ];

          environment = {
            etc = {
              # RKE2 server/agent config file.
              # https://docs.rke2.io/install/configuration
              "rancher/rke2/config.yaml" = {
                text = ''
                  kube-proxy-extra-mount:
                    - "${nftHostPath}:/usr/sbin/nft:ro"
                  ingress-controller: traefik
                '';
              };

              # Registry mirror config for Spegel P2P image sharing.
              # Each mirror entry tells containerd to try the embedded registry
              # before falling back to the upstream registry.
              # https://docs.rke2.io/install/registry_mirror#enabling-registry-mirroring
              "rancher/rke2/registries.yaml" = {
                text = registriesYaml;
              };
            };

            sessionVariables.KUBECONFIG = "/etc/rancher/rke2/rke2.yaml";

            systemPackages = with pkgs; [
              kubectl
              kubernetes-helm
              k9s
            ];
          };

          # Kubernetes kubelet refuses to start with swap enabled.
          assertions = [
            {
              assertion = config.my.disks.swapSize == null;
              message = "RKE2 requires swap to be disabled. Set my.disks.swapSize = null in the host config.";
            }
          ];
        };

      };
  };
}

{ ... }:
{
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

        # TLS SANs are baked into the API server certificate at first boot;
        # changing them later requires certificate rotation.
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

        # Spegel: embedded P2P OCI registry mirror between nodes (port 5001).
        # https://docs.rke2.io/install/registry_mirror
        registryFlags = [ "--embedded-registry" ];

        allExtraFlags =
          tlsSanFlags ++ hardeningFlags ++ etcdSnapshotFlags ++ auditFlags ++ registryFlags ++ cfg.extraFlags;

        # Registries mirrored by Spegel; containerd tries the embedded mirror
        # before falling back to the upstream registry.
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
          # Pre-loaded because security.lockKernelModules = true: modules not
          # listed here cannot be auto-loaded later, and missing iptables
          # targets/matches cause silent rule failures (masquerade, hostPort).
          # Consumers are Cilium (eBPF + iptables masquerade) and the CNI
          # portmap plugin; kube-proxy and IPVS (ipset) modules are obsolete
          # here since kube-proxy is fully replaced.
          boot.kernelModules = [
            "br_netfilter"
            "bridge"
            "veth"
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
            "iptable_filter"
            "iptable_nat"
            "iptable_mangle"
            "iptable_raw"
            "wireguard"
            # VXLAN tunnel device for Cilium pod-to-pod encapsulation.
            "vxlan"
            # XFRM: required by Cilium v1.19+ route reconciler.
            # https://github.com/cilium/cilium/issues/36600
            "xfrm_user"
            # Cilium iptables masquerade and CNI portmap (hostPort) rules.
            "xt_MASQUERADE"
            "xt_multiport"
            "xt_REDIRECT"
            "xt_NETMAP"
          ];

          boot.kernel.sysctl = {
            "fs.inotify.max_user_instances" = 8192;
            "fs.inotify.max_user_watches" = 524288;
            "net.bridge.bridge-nf-call-iptables" = 1;
            "net.bridge.bridge-nf-call-ip6tables" = 1;
          };

          # Cilium CNI: VXLAN tunnel, WireGuard encryption (inert on
          # single-node, active if nodes are added), Hubble observability.
          # Service routing is fully eBPF (kube-proxy replaced — see the
          # HelmChartConfig below and config.yaml).
          # https://docs.rke2.io/networking/basic_network_options
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

          # Cilium HelmChartConfig, applied by RKE2's helm controller.
          #   - kubeProxyReplacement: Cilium implements all service routing
          #     (ClusterIP, NodePort, hostPort, host-namespace) in eBPF.
          #     k8sServiceHost/Port must point at the local API server:
          #     without kube-proxy, ClusterIP routing exists only once
          #     Cilium programs it.
          #     https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/
          #   - operator.replicas=1: the operator binds hostPort 8302; a second
          #     replica can never schedule on a single-node cluster.
          #   - Hubble: flow/DNS/HTTP observability, scraped by VictoriaMetrics.
          #     https://docs.cilium.io/en/stable/observability/hubble/
          systemd.services.rke2-cilium-config = {
            description = "Write Cilium HelmChartConfig for kube-proxy replacement, WireGuard, Hubble";
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
                  kubeProxyReplacement: true
                  k8sServiceHost: "localhost"
                  k8sServicePort: "6443"
                  operator:
                    replicas: 1
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

          # Firewall for a public-internet node.
          # Public: 80/443 (Traefik), 6443 (API server), 51871/udp (WireGuard).
          # Restricted to node IPs: 9345 (supervisor + registry), 10250
          # (kubelet), 2379-2381 (etcd, servers), 5001 (Spegel).
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
              # NixOS strict rpfilter (default with the nftables firewall)
              # silently drops ALL pod->host traffic: pods arrive on lxc*
              # veths but the pod CIDR routes via cilium_host, so the fib
              # reverse-path check fails at PREROUTING. Cilium disables only
              # the sysctl rp_filter, not this nft chain. "loose" still drops
              # martian (unroutable) sources.
              # https://github.com/cilium/cilium/issues/31565
              checkReversePath = "loose";

              allowedTCPPorts = [
                80
                443
                6443
              ];
              allowedUDPPorts = [
                51871
              ];

              # Pod egress through the host FORWARD chain.
              extraForwardRules = [
                "ip saddr 10.42.0.0/16 accept"
                "ip daddr 10.42.0.0/16 accept"
              ];

              # Pods -> host-network services; the input chain is policy drop
              # and this is CNI-agnostic. 9100 node-exporter, 10250 kubelet
              # (metrics-server, exec/logs), 10257/10259 controller-manager
              # and scheduler metrics, 2379 etcd, 4244 hubble-peer.
              # Keep the CIDR in sync with cluster-cidr.
              extraInputRules = lib.concatStringsSep "\n" (
                [ "ip saddr 10.42.0.0/16 tcp dport { 9100, 10250, 10257, 10259, 2379, 4244 } accept" ]
                ++ lib.flatten (
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
              # https://docs.rke2.io/install/configuration
              #
              # disable-kube-proxy MUST be this config-file key: the embedded
              # agent that stages static pod manifests honors only the file
              # form (observed on rke2 1.36.3: the CLI flag alone is ignored
              # and the kube-proxy manifest is re-staged on every start).
              # With the key set the manifest is never written; kubelet's own
              # KUBE-FIREWALL/canary chains remain, which is expected.
              "rancher/rke2/config.yaml" = {
                text = ''
                  disable-kube-proxy: true
                  ingress-controller: traefik
                '';
              };

              # Spegel mirror list for containerd.
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

{ ... }:
{
  den.aspects.consul = {
    nixos =
      { ... }:
      {
        # Consul single-server (the dev-agent pattern): everything on
        # loopback, no ACLs/mTLS. Connect (service mesh) is on by
        # default. https://developer.hashicorp.com/consul/docs
        services.consul = {
          enable = true;
          webUi = true;

          extraConfig = {
            server = true;
            bootstrap_expect = 1;

            # Gossip/RPC on loopback: valid single-node. HTTP/DNS/gRPC
            # already default to client_addr = 127.0.0.1.
            bind_addr = "127.0.0.1";

            # xDS API for Envoy sidecars; disabled (-1) by default.
            # Nomad's grpc socket hook proxies it into alloc netns.
            ports.grpc = 8502;
          };

          # Do not set data_dir or ui_config in extraConfig: the NixOS
          # module merges with right-biased // and they would silently
          # diverge from its StateDirectory/webUi wiring.
        };
      };
  };
}

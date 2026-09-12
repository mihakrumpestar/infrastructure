# consul-cni

Pre-built [consul-cni](https://developer.hashicorp.com/consul/docs/connect/networking/cni) packaged as a Nix flake.

## Standalone build

```sh
nix build path:packages/consul-cni
```

The flake pins its own nixpkgs (`flake.lock`) so it builds independently of the main infrastructure flake.

## Using it

Expose the binary in your Nomad client's CNI path (colon-delimited, discovery is by `cni_path`, not `PATH`):

```nix
services.nomad.settings.client.cni_path =
  "${pkgs.cni-plugins}/bin:${inputs.consul-cni.packages.${system}.default}/bin";
```

## Notes

- The binary is a wrapped derivation: `util-linux` is on its PATH (the plugin shells out for `nsenter`-style operations).
- consul-cni is only invoked when a CNI conflist references `type: "consul-cni"` (Consul transparent proxy). An unused binary in `cni_path` is inert.
- License: MPL-2.0 (upstream).

# Infrastructure

NixOS configuration repository for managing multiple hosts using flakes.

## Repository Structure

```sh
├── hosts/                  # Per-host configurations
├── nixosModules/           # NixOS modules (common/optional)
├── homeManagerModules/     # Home Manager modules and user configs
├── packages/               # Custom packages (flakes)
├── home-modules/           # Custom home-manager modules (flakes)
└── docs/                   # Documentation
```

## Hardware-config

Generate using (on remote):

```sh
nixos-generate-config --show-hardware-config
```

## TPM2 encryption key

Generate per machine TPM2 age key:

```sh
nix-shell -p age-plugin-tpm --command "sudo age-plugin-tpm -g"
```

## Stress test

Stress test:

```sh
nix-shell -p btop --command "btop"
nix-shell -p stress s-tui --command "s-tui"
```

## TODO

- https://github.com/yorukot/superfile
- https://github.com/amadejkastelic/nixos-config/tree/main/hosts/server
- https://nixos-and-flakes.thiscute.world/nixos-with-flakes/modularize-the-configuration
- https://docs.nixbuild.net/remote-builds/

## References

Configs:

- https://github.com/raexera/yuki
- https://github.com/wiedzmin/nixos-config
- https://github.com/Zaechus/nixos-config
- https://github.com/erictossell/nixflakes
- https://github.com/etu/nixconfig
- https://codeberg.org/highghlow/nixos-config
- https://github.com/leoank/neusis: Nvidia Datacenter GPU
- https://github.com/pranjalv123/nix-config: VMs
- https://github.com/abehidek/nix-config: VMs

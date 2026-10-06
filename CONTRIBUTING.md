# Contributing

## Before committing

Run `task ci`: regenerates the flake stats and graph, then runs gitleaks, treefmt, deadnix and statix.

## Tooling decisions

- **tix** (Nix type checker): evaluated 2026-10 on 0.1.0 and removed. `nix eval` already catches real errors, and tix found none; Home Manager stub generation crashes (`attribute 'hm' missing`), generated den stubs are opaque (`aspects: { ... }`), and file-based custom context stubs are ignored. Type annotations in VS Code also do not provide any more info than directly visible in that same scope (no NixOS options, etc.), so it is not really useful for my use cases.

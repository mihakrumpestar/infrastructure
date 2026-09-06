# opencode-plugins

Declarative opencode plugin pinning: `lib.entries` turns pinned npm packages
into opencode `plugin` config entries, and the `opencode-plugins-update` CLI
keeps the pins fresh against npm dist-tags.

## Pins

Consumers declare an `opencodePluginPins` attrset (single source of truth,
rewritten only by `opencode-plugins-update`). Every pin uses the same stanza:

```nix
opencodePluginPins = {
  self-contained-plugin = {
    version = "2.3.3";
    hash = "sha256-..."; # hermetic: tarball fetched by Nix, plugin loads from a store path
  };
  dependency-heavy-plugin = {
    version = "2.2.18";
    hash = null; # npm spec: exact name@version, resolved by opencode's install-once cache
  };
};
```

The hermetic lane works only for self-contained bundles (dependencies inlined
into `dist`, function-shaped exports). opencode 1.18.x never re-resolves bare
or `@latest` specs (its plugin cache key is the spec string, no
revalidation), so every version is pinned explicitly.

## lib.entries

```nix
plugin = inputs.opencode-plugins.lib.entries {
  inherit pkgs;
  pins = opencodePluginPins;
  options.opencode-auto-resume = { /* plugin options -> [ entry, options ] */ };
};
```

## opencode-plugins-update

```bash
# this repo
task update-opencode-plugins                # applies
task update-opencode-plugins -- --dry-run   # report only

# anywhere (nix on PATH required for hermetic hash prefetching)
nix run path:lib/opencode-plugins#opencode-plugins-update -- \
  --file <pins-file> [--dry-run]

# or as a flake input
packages.<system>.opencode-plugins-update
```

## Tests

Unit tests run in the build via the nixpkgs-native `pytestCheckHook`
(`doCheck`, `nativeCheckInputs`, injected fake registry/prefetch backends,
no network, no nix), so every build of the package runs them (home build
via home.packages, and `nix run`/`task update-opencode-plugins`):

```bash
nix build path:lib/opencode-plugins
```

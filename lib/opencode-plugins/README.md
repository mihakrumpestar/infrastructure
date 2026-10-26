# opencode-plugins

Declarative opencode plugin pinning: `lib.entries` turns pinned npm packages into opencode `plugins` config entries, and the `opencode-plugins-update` CLI keeps the pins fresh against npm dist-tags.

## Pins

Consumers declare an `opencodePluginPins` attrset (single source of truth, rewritten only by `opencode-plugins-update`). Every pin uses the same stanza:

```nix
opencodePluginPins = {
  self-contained-plugin = {
    version = "2.3.3";
    hash = "sha256-..."; # hermetic: tarball fetched by Nix, plugin loads from a store path
  };
  dependency-heavy-plugin = {
    version = "2.2.18";
    hash = null; # npm spec: exact name@version installed by opencode v2
  };
};
```

The hermetic lane works only for self-contained ESM bundles (dependencies inlined into `dist`, a v2 entrypoint). It unpacks the npm tarball and generates a root `server.js` that re-exports the package's `exports["./server"]`, `exports["."]`, `module` or `main` entry, because opencode v2 resolves a local plugin directory strictly through `<dir>/server` or `<dir>/index` and ignores package.json exports. The package must declare `"type": "module"`.

A v2 plugin exports a default `{ id, setup }` or `{ id, effect }`; v1 implementations do not run on v2, though a package may support both by exporting a default with a `server` property. opencode v2 installs exact specs under `~/.cache/opencode/npm` and never auto-updates exact versions, so every version is pinned explicitly.

### Why pin instead of letting opencode update them

v2 has update detection, not auto-updating. Startup reuses the cached install (`Npm.add` only installs when no generation exists). Every 24 hours, and on `opencode plugin check`, mutable specs (ranges, tags, unpinned names, mutable git refs) are compared against the registry and marked `outdated`; nothing is installed until `opencode plugin update` or the UI update action runs. Exact versions and full commit pins are immutable by design (`Npm.check` returns false), so they stay on the declared version forever and `plugin update` re-installs the same version. That makes this pin set and its updater the only update path, and keeps the closure reproducible.

## lib.entries

```nix
plugins = inputs.opencode-plugins.lib.entries {
  inherit pkgs;
  pins = opencodePluginPins;
  options.opencode-auto-resume = { /* plugin options -> { package, options } */ };
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

Unit tests run in the build via the nixpkgs-native `pytestCheckHook` (`doCheck`, `nativeCheckInputs`, injected fake registry/prefetch backends, no network, no nix), so every build of the package runs them (home build via home.packages, and `nix run`/`task update-opencode-plugins`):

```bash
nix build path:lib/opencode-plugins
```

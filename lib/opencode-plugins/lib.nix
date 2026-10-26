# Opencode plugin pinning helpers.
#
# opencode v2 installs npm plugin specs with Bun under
# ~/.cache/opencode/npm/<sanitized name@spec> and never auto-updates exact
# versions; local entries must be directories resolved through `<dir>/server`
# or `<dir>/index`. Every pin declares both lanes uniformly:
#
#   hash = "sha256-..."  hermetic: the npm tarball is fetched and unpacked by
#                        Nix, a root `server.js` re-export exposes the v2
#                        entrypoint, and the plugin loads from a read-only
#                        store directory (self-contained ESM bundles only;
#                        runtime deps would need a writable node_modules)
#   hash = null          npm spec: exact name@version installed by opencode v2
#                        (plugins with runtime deps)
#
# Packages must expose a v2 entry (`server` subpath or a root export with
# { id, setup } / { id, effect }); v1 implementations do not run on v2.
#
# Pins live in the consuming module and are rewritten by
# lib/opencode-plugins/opencode_plugins_update.py.
{
  # Build the opencode `plugins` config list from a pins attrset. Entries with
  # a matching `options` attribute become { package = entry; options = attrs; }.
  entries =
    {
      pkgs,
      pins,
      options ? { },
    }:
    let
      # The tarball filename drops the scope ("@scope/name" -> "name").
      unscoped = name: baseNameOf (pkgs.lib.removePrefix "@" name);

      tarballUrl = name: version: "https://registry.npmjs.org/${name}/-/${unscoped name}-${version}.tgz";

      fetchPlugin =
        name: version: hash:
        let
          tarball = pkgs.fetchurl {
            url = tarballUrl name version;
            inherit hash;
          };
        in
        pkgs.runCommand "opencode-plugin-${unscoped name}-${version}"
          {
            nativeBuildInputs = [ pkgs.jq ];
          }
          ''
            mkdir -p $out
            tar -xf ${tarball} -C $out --strip-components=1
            cd $out

            # OpenCode v2 loads a local plugin directory through <dir>/server or
            # <dir>/index and never consults package.json exports. Surface the
            # package's v2 entrypoint under that name.
            entry=$(jq -r '
              def target:
                if type == "string" then .
                elif type == "object" then (.import // .default // .require // empty)
                else empty end;
              (.exports["./server"]? | target)
                // (.exports["."]? | target)
                // .module
                // .main
                // "index.js"
            ' package.json)
            entry=''${entry#./}
            test -f "$entry" || {
              echo "opencode plugin ${name}: no entrypoint at $entry" >&2
              exit 1
            }
            test "$(jq -r '.type // ""' package.json)" = module || {
              echo "opencode plugin ${name}: hermetic lane requires an ESM package" >&2
              exit 1
            }
            cat > server.js <<EOF
            export * from "./$entry";
            export { default } from "./$entry";
            EOF
          '';

      pinEntry =
        name: pin:
        if pin.hash == null then "${name}@${pin.version}" else "${fetchPlugin name pin.version pin.hash}";
    in
    map (
      name:
      if options ? ${name} then
        {
          package = pinEntry name pins.${name};
          options = options.${name};
        }
      else
        pinEntry name pins.${name}
    ) (builtins.attrNames pins);
}

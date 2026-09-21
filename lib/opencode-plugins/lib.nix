# Opencode plugin pinning helpers.
#
# opencode 1.18.x resolves npm plugin specs install-once into
# ~/.cache/opencode/packages/<spec> and never revalidates them; file specs
# (store paths) load directly. Every pin declares both lanes uniformly:
#
#   hash = "sha256-..."  hermetic: the npm tarball is fetched and unpacked by
#                        Nix, the plugin loads from a read-only store path
#                        (self-contained bundles only; runtime deps would need
#                        a writable node_modules)
#   hash = null          npm spec: exact name@version resolved by opencode's
#                        install-once cache (plugins with runtime deps)
#
# Pins live in the consuming module and are rewritten by
# lib/opencode-plugins/opencode_plugins_update.py.
{
  # Build the opencode `plugin` config list from a pins attrset. Entries with
  # a matching `options` attribute become [ entry, options ] tuples.
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
        pkgs.runCommand "opencode-plugin-${unscoped name}-${version}" { } ''
          mkdir -p $out
          tar -xf ${tarball} -C $out --strip-components=1
        '';

      pinEntry =
        name: pin:
        if pin.hash == null then "${name}@${pin.version}" else "${fetchPlugin name pin.version pin.hash}";
    in
    map (
      name:
      if options ? ${name} then
        [
          (pinEntry name pins.${name})
          options.${name}
        ]
      else
        pinEntry name pins.${name}
    ) (builtins.attrNames pins);
}

{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
  pytest ? python3.pkgs.pytest,
}:
stdenvNoCC.mkDerivation {
  pname = "opencode-plugins-update";
  version = "1.0.0";

  src = lib.cleanSourceWith {
    src = ./.;
    filter = path: _type: !lib.hasSuffix "__pycache__" path;
  };

  nativeBuildInputs = [ makeWrapper ];

  # pytestCheckHook (the nixpkgs-native pytest check) runs as a preDist phase
  # against the unpacked source tree; doCheck gates nativeCheckInputs.
  nativeCheckInputs = [
    pytest
    python3.pkgs.pytestCheckHook
  ];

  doCheck = true;

  pytestFlagsArray = [ "-q" ];

  installPhase = ''
    runHook preInstall
    install -Dm555 opencode_plugins_update.py $out/libexec/opencode-plugins-update/opencode_plugins_update.py
    makeWrapper ${python3}/bin/python3 $out/bin/opencode-plugins-update \
      --add-flags "$out/libexec/opencode-plugins-update/opencode_plugins_update.py"
    runHook postInstall
  '';

  # Only python3 (stdlib) at runtime; `nix store prefetch-file` requires nix
  # on PATH by design (uses the invoking user's nix).
  meta = {
    description = "Update opencode plugin pins (opencodePluginPins) against npm dist-tags";
    mainProgram = "opencode-plugins-update";
    platforms = lib.platforms.unix;
  };
}

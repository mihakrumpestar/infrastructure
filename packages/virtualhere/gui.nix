# Inspired by: https://github.com/BatteredBunny/virtualhere-nixos/tree/main
{
  pkgs,
  stdenv,
  fetchurl,
  lib,
  autoPatchelfHook,
  ...
}:
stdenv.mkDerivation rec {
  name = "virtualhere-client-gui";

  src = fetchurl {
    url = "https://www.virtualhere.com/sites/default/files/usbclient/vhuit64";
    hash = "sha256-i1XkR1ERBf/gDHRG8hhkaG759tkkBVYpkh0Zn3ZF8DA=";
  };

  nativeBuildInputs = [
    pkgs.upx
    autoPatchelfHook
  ];

  buildInputs = with pkgs; [
    cairo.out
    fontconfig.lib
    gdk-pixbuf.out
    glib.out
    gtk3.out
    libGL.out
    libgcc.lib
    libxkbcommon.out
    libz.out
    pango.out
    wayland-scanner.out
    wayland.out
    libsm.out
    libx11.out
  ];

  unpackPhase = "true";

  installPhase = ''
    mkdir -p $out/bin
    cp ${src} $out/bin/vhuit64
    chmod 0755 $out/bin/vhuit64
    upx -d $out/bin/vhuit64
    mv $out/bin/vhuit64 $out/bin/virtualhere-client-gui
  '';

  meta = with lib; {
    license = licenses.unfree;
    mainProgram = "virtualhere-client-gui";
  };
}

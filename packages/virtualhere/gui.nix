# Inspired by: https://github.com/BatteredBunny/virtualhere-nixos/tree/main
{
  stdenv,
  fetchurl,
  lib,
  autoPatchelfHook,
  upx,
  python3,
  desktop-file-utils,
  cairo,
  fontconfig,
  gdk-pixbuf,
  glib,
  gtk3,
  libGL,
  libgcc,
  libxkbcommon,
  libz,
  pango,
  wayland-scanner,
  wayland,
  libsm,
  libx11,
}:
stdenv.mkDerivation rec {
  name = "virtualhere-client-gui";
  src = fetchurl {
    url = "https://www.virtualhere.com/sites/default/files/usbclient/vhuit64";
    hash = "sha256-sFQBcgKMUPebTi8lVQ8RyOn05NLmPUj59+D1XP+J7tU=";
  };

  nativeBuildInputs = [
    upx
    python3
    desktop-file-utils
    autoPatchelfHook
  ];

  buildInputs = [
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
    runHook preInstall

    mkdir -p $out/bin
    cp ${src} $out/bin/vhuit64
    chmod 0755 $out/bin/vhuit64
    upx -d $out/bin/vhuit64
    mv $out/bin/vhuit64 $out/bin/virtualhere-client-gui

    # Extract the window icon from the binary: Wayland resolves icons via
    # .desktop -> Icon name and never sees the in-process wxWidgets icon.
    mkdir -p $out/share/icons/hicolor
    python3 ${./extract_icon.py} $out/bin/virtualhere-client-gui virtualhere-client-gui $out/share/icons/hicolor

    # The binary requires UID 0 (the module grants passwordless sudo).
    mkdir -p $out/share/applications
    cat > $out/share/applications/virtualhere-client-gui.desktop <<EOF
    [Desktop Entry]
    Type=Application
    Name=VirtualHere Client
    Comment=Use USB devices over the network
    Exec=sudo -E $out/bin/virtualhere-client-gui
    Icon=virtualhere-client-gui
    StartupWMClass=virtualhere-client-gui
    Terminal=false
    Categories=Network;Utility;
    EOF
    desktop-file-validate $out/share/applications/virtualhere-client-gui.desktop

    runHook postInstall
  '';

  meta = {
    description = "VirtualHere USB Client, graphical user interface";
    homepage = "https://www.virtualhere.com/usb_client_software";
    license = lib.licenses.unfree;
    mainProgram = "virtualhere-client-gui";
    platforms = [ "x86_64-linux" ];
  };
}

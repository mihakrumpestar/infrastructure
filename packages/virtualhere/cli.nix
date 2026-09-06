{
  stdenv,
  fetchurl,
  lib,
  desktop-file-utils,
}:
stdenv.mkDerivation rec {
  name = "vhclientx86_64";

  src = fetchurl {
    url = "https://www.virtualhere.com/sites/default/files/usbclient/${name}";
    hash = "sha256-HIk681IxaDuj1/pU/fvHIlJAFe52TRS+UR0P2gsNkVk=";
  };

  nativeBuildInputs = [
    desktop-file-utils
  ];

  unpackPhase = "true";

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp ${src} $out/bin/${name}
    chmod 0755 $out/bin/${name}
    ln -s $out/bin/${name} $out/bin/virtualhere-client-cli

    # Icon bytes ship in the GUI package (this binary embeds no artwork);
    # the module co-installs both unconditionally, so the name resolves.
    # The binary requires UID 0 (the module grants passwordless sudo).
    mkdir -p $out/share/applications
    cat > $out/share/applications/virtualhere-client-cli.desktop <<EOF
    [Desktop Entry]
    Type=Application
    Name=VirtualHere Client Console
    Comment=Use USB devices over the network (command line client)
    Exec=sudo -E $out/bin/virtualhere-client-cli
    Icon=virtualhere-client-gui
    Terminal=true
    Categories=Network;System;
    EOF
    desktop-file-validate $out/share/applications/virtualhere-client-cli.desktop

    runHook postInstall
  '';

  meta = {
    description = "VirtualHere USB Client, command line interface";
    homepage = "https://www.virtualhere.com/usb_client_software";
    license = lib.licenses.unfree;
    mainProgram = "virtualhere-client-cli";
    platforms = [ "x86_64-linux" ];
  };
}

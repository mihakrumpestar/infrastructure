{
  stdenv,
  fetchurl,
  lib,
  desktop-file-utils,
  version,
  versionCheckHook,
}:
let
  binaryName = "vhclientx86_64";
in
stdenv.mkDerivation rec {
  pname = "virtualhere-client-cli";
  inherit version;

  src = fetchurl {
    url = "https://www.virtualhere.com/sites/default/files/usbclient/${binaryName}";
    hash = "sha256-1m1BoS4RN8463sH4UZh6K/s8xiypaigGRqvNbZxOxVQ=";
  };

  nativeBuildInputs = [
    desktop-file-utils
  ];

  unpackPhase = "true";

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp ${src} $out/bin/${binaryName}
    chmod 0755 $out/bin/${binaryName}
    ln -s $out/bin/${binaryName} $out/bin/virtualhere-client-cli

    # Icon bytes ship in the GUI package (this binary embeds no artwork);
    # the module co-installs both unconditionally, so the name resolves.
    # The binary requires UID 0; the terminal lets sudo prompt if needed.
    mkdir -p $out/share/applications
    cat > $out/share/applications/virtualhere-client-cli.desktop <<EOF
    [Desktop Entry]
    Type=Application
    Name=VirtualHere Client Console
    Comment=Use USB devices over the network (command line client)
    Exec=sudo -- $out/bin/virtualhere-client-cli
    Icon=virtualhere-client-gui
    Terminal=true
    Categories=Network;System;
    EOF
    desktop-file-validate $out/share/applications/virtualhere-client-cli.desktop

    runHook postInstall
  '';

  doInstallCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgramArg = "--help";

  meta = {
    description = "VirtualHere USB Client, command line interface";
    homepage = "https://www.virtualhere.com/usb_client_software";
    license = lib.licenses.unfree;
    mainProgram = "virtualhere-client-cli";
    platforms = [ "x86_64-linux" ];
  };
}

{
  stdenv,
  lib,
  fetchurl,
  perl,
  gnused,
  dpkg,
  makeWrapper,
  autoPatchelfHook,
  libredirect,
  glibc,
}:
stdenv.mkDerivation rec {
  pname = "cups-brother-hll3270cdw";
  version = "1.0.2";
  src = fetchurl {
    url = "https://download.brother.com/welcome/dlf103926/hll3270cdwpdrv-${version}-0.i386.deb";
    sha256 = "1ss0gg51psg798zcj06brswingjgif1kzz15wxzp38vmwzzaa4gq";
  };

  nativeBuildInputs = [
    dpkg
    makeWrapper
    autoPatchelfHook
  ];

  buildInputs = [
    perl
    gnused
    libredirect
    glibc
    # for ❯ nix run nixpkgs#patchelf -- --print-needed brprintconf_hll3270cdw
    #     libc.so.6
  ];

  unpackPhase = "dpkg-deb -x $src .";

  installPhase = ''
    runHook preInstall

    mkdir -p "$out"
    cp -pr opt "$out"
    cp -pr usr/bin "$out/bin"
    rm "$out/opt/brother/Printers/hll3270cdw/cupswrapper/cupswrapperhll3270cdw"

    mkdir -p "$out/lib/cups/filter" "$out/share/cups/model"

    ln -s "$out/opt/brother/Printers/hll3270cdw/cupswrapper/brother_lpdwrapper_hll3270cdw" \
      "$out/lib/cups/filter/brother_lpdwrapper_hll3270cdw"
    ln -s "$out/opt/brother/Printers/hll3270cdw/cupswrapper/brother_hll3270cdw_printer_en.ppd" \
      "$out/share/cups/model/brother_hll3270cdw_printer_en.ppd"

    runHook postInstall
  '';

  # Fix global references and replace auto discovery mechanism
  # with hardcoded values.
  #
  # The configuration binary 'brprintconf_hll3270cdw' and lpd filter
  # 'brhll3270cdwfilter' has hardcoded /opt format strings.  There isn't
  # sufficient space in the binaries to substitute a path in the store, so use
  # libredirect to get it to see the correct path.  The configuration binary
  # also uses this format string to print configuration locations.  Here the
  # wrapper output is processed to point into the correct location in the
  # store.

  postFixup = ''
    substituteInPlace $out/opt/brother/Printers/hll3270cdw/lpd/filter_hll3270cdw \
      --replace "my \$BR_PRT_PATH =" "my \$BR_PRT_PATH = \"$out/opt/brother/Printers/hll3270cdw/\"; #" \
      --replace "PRINTER =~" "PRINTER = \"hll3270cdw\"; #"

    substituteInPlace $out/opt/brother/Printers/hll3270cdw/cupswrapper/brother_lpdwrapper_hll3270cdw \
      --replace "PRINTER =~" "PRINTER = \"hll3270cdw\"; #" \
      --replace "my \$basedir = \`readlink \$0\`" "my \$basedir = \"$out/opt/brother/Printers/hll3270cdw/\""

    #patchelf \
    #  --set-interpreter "${glibc}/lib/ld-linux-x86-64.so.2" \
    #  --add-rpath "${glibc}/lib" \
    #  $out/bin/brprintconf_hll3270cdw

    wrapProgram $out/bin/brprintconf_hll3270cdw \
      --set LD_PRELOAD "${libredirect}/lib/libredirect.so" \
      --set NIX_REDIRECTS /opt=$out/opt

    wrapProgram $out/opt/brother/Printers/hll3270cdw/lpd/brhll3270cdwfilter \
      --set LD_PRELOAD "${libredirect}/lib/libredirect.so" \
      --set NIX_REDIRECTS /opt=$out/opt

    substituteInPlace $out/bin/brprintconf_hll3270cdw \
      --replace \"\$"@"\" \"\$"@\" | LD_PRELOAD= ${gnused}/bin/sed -E '/^(function list :|resource file :).*/{s#/opt#$out/opt#}'"
  '';

  meta = with lib; {
    description = "Brother HL-L3270CDW printer driver";
    license = licenses.unfree;
    sourceProvenance = with sourceTypes; [binaryNativeCode];
    maintainers = with maintainers; [];
    platforms = [
      "x86_64-linux"
      "i686-linux"
    ];
    homepage = "http://www.brother.com/";
    downloadPage = "https://support.brother.com/g/b/downloadend.aspx?c=us&lang=en&prod=hll3270cdw_us_eu_as&os=128&dlid=dlf103926_000&flang=4&type3=10283";
  };
}

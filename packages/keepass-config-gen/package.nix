# KeePassXC-driven configuration generators, inspired by https://github.com/jmylchreest/rosec
{
  lib,
  buildGoModule,
  subPackage,
}:
buildGoModule {
  pname = subPackage;
  version = "0.1.0";

  src = ./.;

  subPackages = [ "cmd/${subPackage}" ];

  vendorHash = "sha256-oVVqV9SQwwxpT8jxC/EfVhgu8vgQRNI2WULLYdm8xV4=";

  ldflags = [
    "-s"
    "-w"
  ];

  meta = {
    description = "Generate configuration from a KeePassXC database";
    homepage = "https://github.com/mihakrumpestar/infrastructure";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = subPackage;
  };
}

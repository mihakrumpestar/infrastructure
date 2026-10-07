# KeePassXC-driven OpenSSH config generator, inspired by https://github.com/jmylchreest/rosec
{ lib, buildGoModule }:
buildGoModule {
  pname = "ssh-config-gen";
  version = "0.1.0";

  src = ./.;

  vendorHash = "sha256-XqWR8Qhww1PzCUxSFoOf80gdtJNimecFx33t9fyUt7c=";

  ldflags = [
    "-s"
    "-w"
  ];

  meta = {
    description = "Generate an OpenSSH config fragment and allowed_signers file from a KeePassXC database";
    homepage = "https://github.com/mihakrumpestar/infrastructure";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "ssh-config-gen";
  };
}

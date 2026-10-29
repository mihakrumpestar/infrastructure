# Admin CLI for the NetBird REST API. The nixpkgs `netbird` binary is a client
# agent (up/down/status) and cannot author peers, policies, routes or DNS.
#
# `netbird-manage` resolves credentials from the Secret Service; the unwrapped
# binary talks to the API directly and exists for tests.
{
  lib,
  buildGoModule,
  fetchFromGitHub,
  jq,
  libsecret,
}:

let
  unwrapped = buildGoModule rec {
    pname = "netbird-manage-unwrapped";
    version = "0.0.0-unstable-2026-07-24";

    src = fetchFromGitHub {
      owner = "TechHutTV";
      repo = "netbird-management-cli";
      rev = "9f33cb2cc41e1035c0d92bef9d27e159d33635f4";
      hash = "sha256-K4q9+DSppxlLuK1E5KaiMcFqhHrQ6tcFKZMjTgqCd4M=";
    };

    # env-precedence: NETBIRD_API_URL plus env-over-file, else a stale config
    # file or the hardcoded cloud URL silently wins.
    # cancel-exit: a declined prompt returns an error, else unattended runs
    # exit 0 having done nothing.
    patches = [
      ./env-precedence.patch
      ./cancel-exit.patch
    ];

    vendorHash = "sha256-g+yaVIx4jxpAQ/+WrGKxhVeliYx7nLQe/zsGpxV4Fn4=";

    ldflags = [
      "-s"
      "-w"
    ];

    # No `subPackages`, so the checkPhase covers every package including the
    # httptest regression suite.
    doCheck = true;

    meta = {
      description = "CLI for the NetBird management API, without the credential wrapper";
      homepage = "https://github.com/TechHutTV/netbird-management-cli";
      license = lib.licenses.gpl3Only;
      mainProgram = "netbird-manage";
      platforms = lib.platforms.linux;
    };
  };
in
unwrapped.overrideAttrs (old: {
  pname = "netbird-manage";

  postInstall = ''
    mv $out/bin/netbird-manage $out/bin/.netbird-manage-unwrapped
    install -m 0555 ${./wrapper.sh} $out/bin/netbird-manage

    # Renamed copy: KeePassXC identifies clients by /proc/<pid>/exe.
    mkdir -p $out/libexec
    cp ${lib.getExe' libsecret "secret-tool"} $out/libexec/netbird-secret-tool
    chmod 0555 $out/libexec/netbird-secret-tool

    substituteInPlace $out/bin/netbird-manage \
      --subst-var-by netbird $out/bin/.netbird-manage-unwrapped \
      --subst-var-by secretTool $out/libexec/netbird-secret-tool \
      --subst-var-by path ${
        lib.makeBinPath [
          libsecret
          jq
        ]
      }
  '';

  meta = old.meta // {
    description = "CLI for the NetBird management API, credentials from the Secret Service";
  };
})

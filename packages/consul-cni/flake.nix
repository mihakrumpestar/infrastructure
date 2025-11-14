{
  description = "A Nix flake for the consul-cni binary";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
    };
  in {
    packages.${system}.consul-cni = let
      consul-cni-unwrapped = pkgs.stdenv.mkDerivation rec {
        pname = "consul-cni-unwrapped";
        version = "1.9.0";

        src = pkgs.fetchurl {
          url = "https://releases.hashicorp.com/consul-cni/${version}/consul-cni_${version}_linux_amd64.zip";
          sha256 = "sha256-dSP6udVYrDOeBK79fnCe4saif88bn8aB1Iq/BSdYM0U=";
        };
        sourceRoot = ".";

        nativeBuildInputs = [pkgs.unzip];

        installPhase = ''
          mkdir -p $out/bin
          unzip $src -d $out/bin
          chmod +x $out/bin/consul-cni
        '';

        meta = with pkgs.lib; {
          description = "Consul CNI plugin for HashiCorp Nomad (pre-built binary)";
          license = licenses.mpl20;
        };
      };
    in
      pkgs.runCommand "consul-cni"
      {
        nativeBuildInputs = [pkgs.makeWrapper];
        propagatedBuildInputs = [consul-cni-unwrapped];
      }
      # We need util-linux for nsenter that consul-cni calls at runtime
      ''
        makeWrapper ${consul-cni-unwrapped}/bin/consul-cni $out/bin/consul-cni \
          --prefix PATH : "${pkgs.lib.makeBinPath [pkgs.util-linux]}"
      ''
      // {meta.mainProgram = "consul-cni";};

    defaultPackage.${system} = self.packages.${system}.consul-cni;
  };
}

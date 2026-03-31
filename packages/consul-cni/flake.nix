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
    packages.${system} = let
      consul-cni-unwrapped = pkgs.stdenv.mkDerivation rec {
        pname = "consul-cni-unwrapped";
        version = "1.9.5";

        src = pkgs.fetchurl {
          url = "https://releases.hashicorp.com/consul-cni/${version}/consul-cni_${version}_linux_amd64.zip";
          sha256 = "sha256-zUSht1zouaXYVP67lAs6Xx6/TfoXqy8G7YHLNAhyx8U=";
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
      consul-cni-wrapped = pkgs.runCommand "consul-cni"
        {
          nativeBuildInputs = [pkgs.makeWrapper];
          propagatedBuildInputs = [consul-cni-unwrapped];
        }
        ''
          makeWrapper ${consul-cni-unwrapped}/bin/consul-cni $out/bin/consul-cni \
            --prefix PATH : "${pkgs.lib.makeBinPath [pkgs.util-linux]}"
        ''
        // {meta.mainProgram = "consul-cni";};
    in {
      consul-cni = consul-cni-wrapped;
      default = consul-cni-wrapped;
    };
    defaultPackage.${system} = self.packages.${system}.consul-cni;
  };
}

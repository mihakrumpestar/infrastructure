{ ... }:
{
  den.aspects.nix = {
    nixos =
      { pkgs, ... }:
      {
        nix = {
          package = pkgs.nixVersions.latest;
          # Also tested lix: pkgs.lixPackageSets.latest.lix
          # but it is about 12% slower than nix actually

          settings = {
            experimental-features = [
              "nix-command"
              "flakes"
            ];

            download-buffer-size = 128 * 1024 * 1024; # 128MB - fixes download buffer warning

            # Third-party cache. Cachix publishes priority 41, so query order
            # is cache.nixos.org (40) and then this.
            substituters = [ "https://nix-community.cachix.org" ];
            trusted-public-keys = [
              "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
            ];
          };
          # Optimize store
          optimise = {
            # Manually: nix-store --optimise
            automatic = true;
            dates = [ "weekly" ];
          };

          # Garbage collection
          gc = {
            # Manually: nix-collect-garbage --delete-older-than 14d
            automatic = true;
            dates = "weekly";
            options = "--delete-older-than 14d";
          };
        };

        nixpkgs.config.allowUnfree = true;
      };
  };
}

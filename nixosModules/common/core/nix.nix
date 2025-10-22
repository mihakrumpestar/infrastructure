{config, ...}: {
  config = {
    nix = {
      settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];

        extra-sandbox-paths = ["/tmp"];
      };

      # Optimize store
      optimise = {
        # Manually: nix-store --optimise
        automatic = true;
        dates = ["weekly"];
      };

      # Garbage collection
      gc = {
        # Manually: nix-collect-garbage --delete-older-than 14d
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 14d";
      };
    };

    system.stateVersion = config.system.nixos.release;

    nixpkgs.config = {
      allowUnfree = true;
    };
  };
}

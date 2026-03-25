{
  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];

      download-buffer-size = 67108864; # 64MB - fixes download buffer warning

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

  nixpkgs.config = {
    allowUnfree = true;
  };
}

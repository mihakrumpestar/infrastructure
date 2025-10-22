{pkgs, ...}: {
  my = {
    disks = {
      bootDisk = "/dev/nvme0n1";
      swapSize = "32G";
      encryptRoot = "fido2";
    };

    hostType = "client";

    networking.homeWifi.enable = true;

    de.plasma.enable = true;
  };

  programs.steam = {
    enable = true; # UNFREE license

    extraPackages = with pkgs; [
      jq
      cabextract
      wget
      pkgsi686Linux.libpulseaudio
    ];

    protontricks.enable = true; # Manually run: protontricks 9420 dlls d3dx9 xact
    gamescopeSession.enable = true;
  };

  # Launcher options: PROTON_NO_FSYNC=1 PROTON_NO_ESYNC=1 %command% /fullscreen
}

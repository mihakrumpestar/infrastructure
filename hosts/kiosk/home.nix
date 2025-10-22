{
  pkgs,
  zen-browser,
  ...
}: {
  home-manager.users.kiosk = {
    home.packages = with pkgs; [
      zen-browser.packages."${system}".default
    ];
  };
}

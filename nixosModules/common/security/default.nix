{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  config = mkIf (config.my.hostType == "client" && config.my.hostSubType != "kiosk") {
    # SSH agent
    programs.ssh = {
      startAgent = true;
      enableAskPassword = true;
      askPassword = "${pkgs.kdePackages.ksshaskpass}/bin/ksshaskpass";
    };

    services.paretosecurity.enable = true;
  };
}

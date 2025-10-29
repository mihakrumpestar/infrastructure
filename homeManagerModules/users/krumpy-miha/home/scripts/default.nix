{pkgs, ...}: {
  home.packages = with pkgs; [
    #(writeShellScriptBin "color-picker" ''
    #  #!/usr/bin/env bash
    #  ${pkgs.curl}/bin/curl https://example.com
    #  ${pkgs.jq}/bin/jq '.' response.json
    #'')

    (writeShellApplication {
      name = "color-picker";
      runtimeInputs = [
        kdePackages.qttools # qdbus
        gnused # sed
        wl-clipboard
      ];
      text = builtins.readFile ./color-picker.sh;
    })

    (writeShellApplication {
      name = "git-clean-branch-history";
      runtimeInputs = [
        git
      ];
      text = builtins.readFile ./git-clean-branch-history.sh;
    })

    (writeShellApplication {
      name = "nuke";
      runtimeInputs = [
      ];
      text = builtins.readFile ./nuke.sh;
    })
  ];
}

{ ... }:
{
  den.aspects.shell-fonts = {
    nixos =
      { pkgs, ... }:
      {
        # Fonts
        fonts.packages = with pkgs; [
          meslo-lgs-nf # font for starship
          SDL2_ttf
          carlito
          dejavu_fonts
          noto-fonts
          noto-fonts-cjk-sans
          noto-fonts-color-emoji
          font-awesome
          hack-font
          liberation_ttf
          roboto
          roboto-mono
          ubuntu-classic
          fira-code
          fira-code-symbols
          mplus-outline-fonts.githubRelease
          dina-font
          proggyfonts
          font-adobe-75dpi
          font-adobe-100dpi
        ];
      };
  };
}

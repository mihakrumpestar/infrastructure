{ ... }:
{
  den.aspects.shell-fonts = {
    nixos =
      { lib, pkgs, ... }:
      {
        # Fonts
        fonts.packages = with pkgs; [
          meslo-lgs-nf # font for starship
          SDL2_ttf
          carlito
          dejavu_fonts
          noto-fonts
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
          freefont_ttf
          gyre-fonts # TrueType substitutes for standard PostScript fonts
          unifont
          # Removed: font-adobe-75dpi/100dpi (bitmap, hijacked the "Helvetica" family)
          # Removed: noto-fonts-cjk-sans/serif (their Latin Extended glyphs, e.g.
          # c caron, are drawn small and browser per-glyph fallback picked them
          # for Segoe UI/system-ui stacks)
        ];

        # graphical-desktop auto-enables this set and it includes the removed
        # CJK fonts; disabled so this file stays the single font source of truth.
        fonts.enableDefaultPackages = lib.mkForce false;

        # Ban bitmap fonts so scalable ones always win family resolution.
        fonts.fontconfig.allowBitmaps = false;
      };
  };
}

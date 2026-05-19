{ den, ... }:
{
  den.aspects.shell = {
    includes = [
      den.aspects.shell-fonts
      den.aspects.shell-packages
      den.aspects.shell-zsh
      den.aspects.shell-starship
    ];
  };
}

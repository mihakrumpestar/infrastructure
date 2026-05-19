{ inputs, ... }:
{
  # You may import it in your own flake using:
  # imports = [ (inputs.den.namespace "home" [ inputs.infrastructure ]) ]
  imports = [ (inputs.den.namespace "home" true) ];
}

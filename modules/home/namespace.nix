{ inputs, ... }:
{
  imports = [ (inputs.den.namespace "home" true) ];
}

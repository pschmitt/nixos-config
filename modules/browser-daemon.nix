{
  inputs,
  ...
}:
{
  imports = [
    inputs.browser-daemon.nixosModules.default
  ];
}

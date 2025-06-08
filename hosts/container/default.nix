{ pkgs, ... }:
{
  imports = [ ];

  environment.systemPackages = with pkgs; [
    # Add your packages here
    hello
  ];
}

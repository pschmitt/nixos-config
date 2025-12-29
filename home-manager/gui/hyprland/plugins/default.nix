{
  imports = [
    # NOTE Below plugins conflict with one another!
    # ./hyprexpo.nix
    # ./hyprspace.nix
    # ./hyprtasking.nix

    ./hyprgrass.nix
    ./hypr-dynamic-cursors.nix
    ./quickshell-overview.nix
    ./xtra-dispatchers.nix
  ];
}

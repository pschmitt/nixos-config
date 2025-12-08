{
  imports = [
    # NOTE Below plugins conflict with one another!
    # ./hyprexpo.nix
    # ./hyprspace.nix
    # ./hyprtasking.nix

    ./hyprgrass.nix
    ./hypr-dynamic-cursors.nix
    ./qs-hyprview.nix
    ./xtra-dispatchers.nix
  ];
}

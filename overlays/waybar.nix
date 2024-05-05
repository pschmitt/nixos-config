{ final, prev }:

{
  waybar = prev.waybar.overrideAttrs (oldAttrs: {
    pname = "waybar";
    version = "2024-05-05";

    src = prev.fetchFromGitHub {
      owner = "Alexays";
      repo = "Waybar";
      rev = "231d6972d7a023e9358ab7deda509baac49006cb";
      sha256 = "sha256-mCQdrn0Y3oOVZP/CileWAhuBX6aARBNrfxyqJBB4NxA=";
    };
  });
}

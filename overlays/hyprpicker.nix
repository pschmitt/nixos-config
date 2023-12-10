{ final, prev }:

{
  hyprpicker-git = prev.hyprpicker.overrideAttrs (oldAttrs: {
    pname = "hyprpicker-git";
    version = "b6130e";

    src = prev.fetchFromGitHub {
      owner = "hyprwm";
      repo = "hyprpicker";
      rev = "b6130e3901ed5c6d423f168705929e555608d870";
      hash = "sha256-x+6yy526dR75HBmTJvbrzN+sXINVL26yN5TY75Dgpwk=";
    };
  });
}

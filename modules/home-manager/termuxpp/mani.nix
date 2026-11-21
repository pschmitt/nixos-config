{ inputs, lib, ... }:
{
  imports = [
    ../../../home-manager/devel/mani.nix
    # The work repository list (work.yaml) lives in the private repo.
    (inputs.nixos-config-private.outPath + "/hm/mani.nix")
  ];

  # mani.nix brings the package and the project lists. The guest has no
  # systemd, so do not ship its update units and timers (the nightly job runs
  # mani instead).
  xdg.configFile =
    lib.genAttrs
      [
        "systemd/user/mani.service"
        "systemd/user/mani-work.service"
        "systemd/user/mani.timer"
        "systemd/user/mani-work.timer"
        "systemd/user/timers.target.wants/mani.timer"
        "systemd/user/timers.target.wants/mani-work.timer"
      ]
      (_: {
        enable = lib.mkForce false;
      });
}

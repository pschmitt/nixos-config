{ pkgs, ... }:
{
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "podman-run-mullvad" ''
      exec ${pkgs.podman}/bin/podman run --net=ns:/run/netns/mullvad "$@"
    '')
  ];
}

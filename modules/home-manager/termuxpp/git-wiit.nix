# git.wiit.one over HTTPS with the personal access token, on the phones: no
# ssh key has to be registered for every phone and the token is already in
# SOPS (the same one glab uses on the desktop).
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  forge = "git.wiit.one";
  token = config.sops.secrets."glab/${forge}/token".path;

  # Answers `get` for https://git.wiit.one only. The token is read from the
  # SOPS secret when git asks, so it stays out of the Nix store and out of
  # the git config.
  helper = pkgs.writeShellScript "git-credential-wiit" ''
    [ "$1" = get ] || exit 0
    protocol="" request_host=""
    while IFS='=' read -r key value; do
      [ -n "$key" ] || break
      case "$key" in
        protocol) protocol="$value" ;;
        host) request_host="$value" ;;
      esac
    done
    [ "$protocol" = https ] && [ "$request_host" = ${forge} ] || exit 0
    printf 'username=oauth2\npassword=%s\n' "$(cat ${lib.escapeShellArg token})"
  '';
in
{
  # The work identity (name, email, SSH signing) lives in the private repo.
  imports = [ (inputs.nixos-config-private.outPath + "/hm/git-work.nix") ];

  programs.git.settings = {
    credential."https://${forge}".helper = "${helper}";
    # Remotes written as ssh (work.yaml, copied URLs) use the token as well.
    url."https://${forge}/".insteadOf = [
      "git@${forge}:"
      "ssh://git@${forge}/"
    ];
  };
}

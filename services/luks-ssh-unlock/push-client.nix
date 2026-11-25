{ inputs, ... }:
{
  imports = [ (inputs.nixos-config-private.outPath + "/services/luks-ssh-unlock-push-client.nix") ];
  services.luks-ssh-unlock.activationScript.push.enable = true;
}

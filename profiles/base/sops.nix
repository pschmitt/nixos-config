{ inputs, ... }:

{
  sops = {
    defaultSopsFile = inputs.nixos-config-private.outPath + "/secrets/nixos-shared.sops.yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    age.generateKey = false;
  };
}

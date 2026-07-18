{ config, lib, ... }:

let
  user = config.mainUser.username;
  sopsFile = config.host.sopsFile;

  algs = [
    "ed25519"
    "rsa"
  ];
  kinds = [
    "privkey"
    "pubkey"
  ];

  secretName = alg: kind: "users/${user}/ssh/${alg}/${kind}";

  sopsSecrets = builtins.listToAttrs (
    builtins.concatMap (
      alg:
      map (kind: {
        name = secretName alg kind;
        value = {
          inherit sopsFile;
          mode = if kind == "privkey" then "0400" else "0444";
        };
      }) kinds
    ) algs
  );

  homeFiles = builtins.listToAttrs (
    builtins.concatMap (
      alg:
      let
        base = ".ssh/hm/id_${alg}";
      in
      [
        {
          name = base;
          value.source =
            config.lib.file.mkOutOfStoreSymlink
              config.sops.secrets.${secretName alg "privkey"}.path;
        }
        {
          name = "${base}.pub";
          value.source =
            config.lib.file.mkOutOfStoreSymlink
              config.sops.secrets.${secretName alg "pubkey"}.path;
        }
      ]
    ) algs
  );
in
# Per-host SSH key secrets live in host.sopsFile; only hosts that actually hold
# them opt in via host.provisionSshKeys (set by the bridge / host file).
lib.mkMerge [
  (lib.mkIf config.host.provisionSshKeys {
    sops.secrets = sopsSecrets;
    home.file = homeFiles;
  })

  (lib.mkIf config.host.manageAuthorizedKeys {
    home.file.".ssh/authorized_keys".text =
      lib.concatStringsSep "\n" (config.mainUser.authorizedKeys ++ config.mainUser.extraAuthorizedKeys)
      + "\n";
  })
]

{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  sopsFile = inputs.nixos-config-private.outPath + "/secrets/nixos-gpg.sops.yaml";

  keys = [
    {
      name = "private";
      key = "gpg/private/privateKey";
      pass = "gpg/private/passphrase";
    }
    {
      name = "work";
      key = "gpg/work/privateKey";
      pass = "gpg/work/passphrase";
    }
  ];

  sopsSecrets = builtins.listToAttrs (
    builtins.concatMap (entry: [
      {
        name = entry.key;
        value = {
          inherit sopsFile;
          mode = "0400";
        };
      }
      {
        name = entry.pass;
        value = {
          inherit sopsFile;
          mode = "0400";
        };
      }
    ]) keys
  );

  mkImportScript =
    entry:
    pkgs.writeShellScript "hm-gpg-import-${entry.name}" ''
      set -euo pipefail

      export GNUPGHOME="${config.programs.gpg.homedir}"

      ${pkgs.coreutils}/bin/mkdir -p "$GNUPGHOME"
      # ${pkgs.coreutils}/bin/touch "$GNUPGHOME/pubring.kbx"

      import_key() {
        local key_path="$1"
        local pass_path="$2"
        local label="$3"

        if [[ ! -s "$key_path" ]]
        then
          echo "GPG key ($label) missing at $key_path" >&2
          return 1
        fi

        if [[ ! -s "$pass_path" ]]
        then
          echo "Passphrase for ($label) missing at $pass_path" >&2
          return 1
        fi

        echo "Importing GPG key ($label)"
        ${pkgs.gnupg}/bin/gpg --batch --yes --pinentry-mode loopback \
          --passphrase-file "$pass_path" --import "$key_path"

        local fpr
        fpr="$(${pkgs.gnupg}/bin/gpg --batch --with-colons \
          --pinentry-mode loopback --passphrase-file "$pass_path" \
          --import-options show-only --import "$key_path" \
          | ${pkgs.gawk}/bin/awk -F: '/^fpr:/{print $10; exit}')"

        if [[ -z "$fpr" ]]
        then
          echo "Could not determine GPG fingerprint for ($label)" >&2
          return 1
        fi

        printf '%s:6:\n' "$fpr" | \
          ${pkgs.gnupg}/bin/gpg --batch --yes --import-ownertrust
      }

      import_key \
        "${config.sops.secrets.${entry.key}.path}" \
        "${config.sops.secrets.${entry.pass}.path}" \
        "${entry.name}"
    '';
in
{
  sops.secrets = sopsSecrets;

  home.packages = [ pkgs.pinentry-guess ];

  # The agent itself is started by NixOS (programs.gnupg.agent); this is its
  # config in GNUPGHOME (formerly in yadm).
  xdg.configFile."gnupg/gpg-agent.conf".text = ''
    # https://wiki.archlinux.org/index.php/GnuPG#Unattended_passphrase
    allow-loopback-pinentry
    pinentry-program ${lib.getExe pkgs.pinentry-guess}

    # Increase timeout
    max-cache-ttl 28800
    default-cache-ttl 28800

    # SSH
    enable-ssh-support

    # SSH timeouts
    default-cache-ttl-ssh 28800
    max-cache-ttl-ssh 28800
  '';

  programs.gpg = {
    enable = true;
    homedir = "${config.xdg.configHome}/gnupg";
  };

  systemd.user.services = builtins.listToAttrs (
    builtins.map (entry: {
      name = "gpg-import-${entry.name}";
      value = {
        Unit = {
          Description = "Import GPG key (${entry.name})";
          After = [ "sops-nix.service" ];
          Wants = [ "sops-nix.service" ];
        };
        Service = {
          Type = "oneshot";
          Environment = [ "GNUPGHOME=${config.programs.gpg.homedir}" ];
          # Allow subsequent start requests (e.g., when yadm-clone is
          # triggered during activation) to re-run the import.
          RemainAfterExit = false;
          ExecStart = mkImportScript entry;
        };
        Install = {
          WantedBy = [ "default.target" ];
        };
      };
    }) keys
  );
}

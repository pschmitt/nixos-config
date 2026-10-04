{
  config,
  lib,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  completion = pkgs.linkFarm "zsh-completion-ipmi" [
    {
      name = "_ipmi";
      path = pkgs.writeText "zsh-completion-ipmi" ''
        #compdef ipmi

        _ipmi_files_with_info() {
          [[ $CURRENT -gt 2 ]] && return

          local -a files
          local config_dir="''${IPMI_CONFIG_DIR:-''${XDG_CONFIG_DIR:-$HOME/.config}}/ipmi"
          local file desc

          for file in "$config_dir"/*(N)
          do
            source <(grep -E '^DEVICE_' "$file")
            desc="''${DEVICE_CLUSTER} - ''${DEVICE_ROLE:-Unknown}"
            files+=("''${file:t}:''${desc}")
          done

          _describe -t files 'IPMI Targets' files -V1
        }

        _ipmi_files_with_info "$@"
      '';
    }
  ];
in
{
  xdg.configFile."zsh/completions/_ipmi".source = "${completion}/_ipmi";

  programs.zsh.initContent = lib.mkIf (!termuxMode) (
    lib.mkOrder 520 ''
      fpath=(${completion} $fpath)
    ''
  );
}

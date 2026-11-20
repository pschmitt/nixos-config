{ pkgs, ... }:
{
  home.packages = with pkgs; [
    jc
    jq
    jsonrepair
    # inputs.mq.packages.${pkgs.stdenv.hostPlatform.system}.mq
    yq-go
  ];

  # Our own jc parsers (jc --cmd-wifi-status, --vcf), formerly in yadm
  xdg.dataFile."jc/jcparsers" = {
    source = ./jcparsers;
    recursive = true;
  };
}

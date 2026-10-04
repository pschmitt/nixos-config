{ lib, pkgs, ... }:
let
  completion = pkgs.linkFarm "zsh-completion-whatsmy" [
    {
      name = "_whatsmy";
      path = pkgs.writeText "zsh-completion-whatsmy" ''
        #compdef whatsmy

        _whatsmy() {
          local -a flags=(
            'ap:Base station (wifi AP)'
            'bssid:Wifi BSSID'
            'dns:DNS'
            'essid:Wifi ESSID'
            'frequency:CPUffrequency'
            'gateway:Default gateway'
            'interfaces:NIC interfaces'
            'load:Load average'
            'local-ip:Local IPv4 address'
            'local-ip6:Local IPv6 address'
            'mac:MAC Address'
            'nic:Interface names'
            'public_ip:Public (WAN) IP address'
            'temperature:lm-sensors temps'
            'weather:Current weather'
            'wireless:Wireless interface names'
          )

          _arguments '*:: :->subcmds' && return 0
          _describe -t commands "whatsmy commands" flags -V1
        }

        _whatsmy "$@"
      '';
    }
  ];
in
{
  programs.zsh.initContent = lib.mkOrder 520 ''
    fpath=(${completion} $fpath)
  '';
}

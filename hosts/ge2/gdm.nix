{ pkgs, ... }:
{
  # GDM monitor configuration
  systemd.tmpfiles.rules = [
    "L+ /run/gdm/.config/monitors.xml - - - - ${pkgs.writeText "gdm-monitors.xml" ''
      <monitors version="2">
        <configuration>
          <layoutmode>physical</layoutmode>
          <logicalmonitor>
            <x>0</x>
            <y>0</y>
            <scale>1</scale>
            <monitor>
              <monitorspec>
                <connector>DP-4</connector>
                <vendor>LEN</vendor>
                <product>M14</product>
                <serial>V904MRZR</serial>
              </monitorspec>
              <mode>
                <width>1920</width>
                <height>1080</height>
                <rate>60.000</rate>
              </mode>
            </monitor>
          </logicalmonitor>
          <logicalmonitor>
            <x>1920</x>
            <y>0</y>
            <scale>1</scale>
            <primary>yes</primary>
            <monitor>
              <monitorspec>
                <connector>DP-5</connector>
                <vendor>GSM</vendor>
                <product>LG HDR WQHD</product>
                <serial>0x000e0531</serial>
              </monitorspec>
              <mode>
                <width>3440</width>
                <height>1440</height>
                <rate>59.973</rate>
              </mode>
            </monitor>
          </logicalmonitor>
          <disabled>
            <monitorspec>
              <connector>eDP-1</connector>
              <vendor>AUO</vendor>
              <product>0x31a6</product>
              <serial>0x00000000</serial>
            </monitorspec>
            <monitorspec>
              <connector>DP-6</connector>
              <vendor>LNX</vendor>
              <product>PiKVM V3</product>
              <serial>CAFEBABE     </serial>
            </monitorspec>
          </disabled>
        </configuration>
      </monitors>
    ''}"
  ];
}

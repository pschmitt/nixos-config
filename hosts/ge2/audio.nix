_:
let
  card = "pci-0000_00_1f.3-platform-sof_sdw.HiFi";
  configure = direction: endpoint: properties: {
    matches = [ { "node.name" = "alsa_${direction}.${card}__${endpoint}"; } ];
    actions.update-props = properties;
  };
in
{
  services.pipewire.wireplumber.extraConfig."90-ge2-audio"."monitor.alsa.rules" = [
    (configure "output" "Speaker__sink" {
      "node.description" = "Laptop Speakers";
      "priority.session" = 800;
    })
    (configure "output" "Headphones__sink" { "node.description" = "Wired Headphones"; })
    (configure "output" "HDMI1__sink" {
      "node.description" = "Display Audio 1";
      "priority.session" = 1200;
    })
    (configure "input" "Mic__source" { "node.description" = "Laptop Microphone"; })
    (configure "input" "Headset__source" { "node.description" = "Wired Headset Microphone"; })
    {
      # These unused display channels can be re-enabled if another display
      # needs audio; HDMI numbering does not necessarily follow physical ports.
      matches = [
        { "node.name" = "alsa_output.${card}__HDMI2__sink"; }
        { "node.name" = "alsa_output.${card}__HDMI3__sink"; }
      ];
      actions.update-props."node.disabled" = true;
    }
  ];

  services.pipewire.wireplumber.extraConfig."90-ge2-audio"."monitor.bluez.rules" = [
    {
      matches = [ { "node.name" = "~bluez_output.*"; } ];
      actions.update-props."priority.session" = 1400;
    }
  ];
}

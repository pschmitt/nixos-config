_:
let
  card = "pci-0000_00_1f.3-platform-sof_sdw.HiFi";
  rename = direction: endpoint: description: {
    matches = [ { "node.name" = "alsa_${direction}.${card}__${endpoint}"; } ];
    actions.update-props."node.description" = description;
  };
in
{
  services.pipewire.wireplumber.extraConfig."90-ge2-audio"."monitor.alsa.rules" = [
    (rename "output" "Speaker__sink" "Laptop Speakers")
    (rename "output" "Headphones__sink" "Wired Headphones")
    (rename "output" "HDMI1__sink" "Display Audio 1")
    (rename "input" "Mic__source" "Laptop Microphone")
    (rename "input" "Headset__source" "Wired Headset Microphone")
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
}

{ config, ... }:
{
  gtk = {
    enable = true;
    # https://hoverbear.org/blog/declarative-gnome-configuration-in-nixos/
    gtk3 = {
      bookmarks = [
        "file://${config.home.homeDirectory}/devel/private 💻 dev-p"
        "file://${config.home.homeDirectory}/devel/work 💻 dev-w"
        "file://${config.home.homeDirectory}/Backups 💾 backups"
        "file://${config.home.homeDirectory}/Documents 📄 documents"
        "file://${config.home.homeDirectory}/Downloads 📥 downloads"
        "file://${config.home.homeDirectory}/Music 🎵 music"
        # "file://${config.home.homeDirectory}/Public 📂 public"
        "file://${config.home.homeDirectory}/Pictures 📷 pictures"
        # "file://${config.home.homeDirectory}/Templates 📄 templates"
        "file://${config.home.homeDirectory}/Videos 🎥 videos"
        "file:///tmp 🗑 tmp"
        "file:///mnt/data 🖧 data"
        "file:///mnt/turris 🖧 turris"
        "file:///mnt/hass 🖧 hass"
      ];
    };
  };
}

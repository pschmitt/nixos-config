#!/usr/bin/env bash

# Remove conflicting packages
packages_to_remove=(
  hyprland
  xdg-desktop-portal-wlr
  xdg-desktop-portal-wlr-git
  xdg-desktop-portal-wlr-kde
)

for p in "${packages_to_remove[@]}"
do
  if pacman -Qi "$p" &> /dev/null
  then
    sudo pacman -Rdd --noconfirm "$p"
  fi
done

yay -S --needed --noconfirm \
  hyprland-git \
  waybar-hyprland \
  wlr-randr \
  nwg-displays \
  xdg-desktop-portal-hyprland \
  gtklock-playerctl-module \
  gtklock-userinfo-module \
  gtklock \
  pyprland \
  cliphist \
  wl-clip-persist-git \
  hyprprop-git \
  wleave-git \
  hyprpaper \
  hyprpicker-git \
  swhkd-git \
  chayang-git


# Addons
# pipx install pyprland
cargo install --git=https://github.com/nate-sys/hypr-empty

# hyprload
if [[ ! -r ~/.local/share/hyprload/hyprload.so ]]
then
  curl -sSL https://raw.githubusercontent.com/Duckonaut/hyprload/main/install.sh | \
    sed 's#pkexec #sudo #' | bash
fi

# Install hyprland-wrapped.desktop
sudo cp -av ~/.config/hypr/hyprland-wrapped.desktop \
  /usr/share/wayland-sessions/hyprland-wrapped.desktop

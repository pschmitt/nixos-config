{ pkgs, ... }:
{
  services.kmscon.config."xkb-keymap" = "${pkgs.custom-keymaps}/share/keymaps/custom/hhkb-de.xkb";
}

{ ... }:
{
  # browser-daemon is the only headless browser we run: a Chrome per connection,
  # so interactive agent browsers and automation workers do not interfere.
  # Dashboard (behind Authelia): https://browser.<host>.<mesh domain>/
  imports = [
    ../services/headless-browsers/browser-daemon.nix
  ];
}

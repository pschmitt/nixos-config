{ ... }:
{
  # Browserless is the only headless browser we run: a Chrome per connection,
  # so interactive agent browsers and automation workers do not interfere.
  # Dashboard (behind Authelia): https://browserless.<host>.<mesh domain>/debugger/
  imports = [
    ../services/headless-browsers/browserless.nix
  ];
}

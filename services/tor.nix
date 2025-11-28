{
  services.tor = {
    enable = true;
    openFirewall = false;
    relay.enable = false;
    client.enable = true;
  };
}

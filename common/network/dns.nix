_: {
  services.resolved = {
    enable = true;
    settings.Resolve = {
      DNSOverTLS = false;
      DNSSEC = false;
      # Domains = [ "~." ];
      LLMNR = true;
      FallbackDNS = [
        "1.1.1.1#one.one.one.one"
        "1.0.0.1#one.one.one.one"
      ];
    };
  };
}

_: {
  services.resolved = {
    enable = true;
    dnssec = "false";
    llmnr = "true";
    # domains = [ "~." ];
    fallbackDns = [
      "1.1.1.1#one.one.one.one"
      "1.0.0.1#one.one.one.one"
    ];
  };
}

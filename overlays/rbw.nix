{ final, prev }:
{
  rbw = prev.rbw.overrideAttrs (old: rec {
    pname = "rbw";
    # version = "1.14.1";
    version = "1.15.0";

    src = prev.fetchFromGitHub {
      owner = "pschmitt";
      repo = pname;
      rev = "json-1.15";
      hash = "sha256-3ZrKXaXal4J/qSl/pXwV1+eIPGQJgLSIGcQ+4XHsJFg=";
    };

    # cargoHash = null;

    cargoDeps = final.rustPlatform.fetchCargoVendor {
      inherit src;
      # hash = "sha256-H1DSP3Kyklv8ncn7zDP0njDlwB8Qh+h7mqWRAJcpWrE=";
      hash = "sha256-N4IxnAXDvD+vp3LUB9CKYM+1C5i1Flihk+Pfb2c5IWY=";
    };
  });
}

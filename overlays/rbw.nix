{ final, prev }:
{
  rbw = prev.rbw.overrideAttrs (old: rec {
    pname = "rbw";
    version = "1.14.1";

    src = prev.fetchFromGitHub {
      owner = "pschmitt";
      repo = pname;
      rev = "json-1.14";
      hash = "sha256-d44LaEtZD68ucBlfp7Pwd3mvV09U5ITNJSi5LDVwq1Q=";
    };

    # cargoHash = null;

    cargoDeps = final.rustPlatform.fetchCargoVendor {
      inherit src;
      hash = "sha256-H1DSP3Kyklv8ncn7zDP0njDlwB8Qh+h7mqWRAJcpWrE=";
    };
  });
}

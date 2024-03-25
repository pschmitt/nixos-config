{ final, prev }:
{
  amrnb = prev.amrnb.overrideAttrs (oldAttrs: {
    src = final.fetchurl {
      # Below is the default, upstream src. It currently (2024.03.25) is offline.
      # url = "http://www.penguin.cz/~utx/ftp/amr/amrnb-11.0.0.0.tar.bz2";
      url = "https://repo.nepustil.net/distfiles/libamrnb/amrnb-11.0.0.0.tar.bz2";
      sha256 = "1qgiw02n2a6r32pimnd97v2jkvnw449xrqmaxiivjy2jcr5h141q";
    };
  });
}

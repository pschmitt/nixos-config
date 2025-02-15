{ final, prev }:
{
  rbw = prev.rbw.overrideAttrs (oldAttrs: {
    patches = (oldAttrs.patches or [ ]) ++ [
      # Add --raw option to search command
      # https://github.com/doy/rbw/pull/232
      (prev.fetchpatch {
        url = "https://github.com/doy/rbw/pull/232.patch";
        sha256 = "sha256-aBZdcB//Nr24ReRPHKp42y/JuBK208bUxfK4iexv8x0=";
      })
      # Add --raw option to list command
      # https://github.com/doy/rbw/pull/241
      (prev.fetchpatch {
        url = "https://github.com/doy/rbw/pull/241.patch";
        sha256 = "sha256-tTFD45n3PPFnjD1LfiqBoLtMJZ83fbJMM2DUbQeoGuc=";
      })
    ];
  });
}

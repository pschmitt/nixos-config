{
  cmake,
  fetchFromGitHub,
  lib,
  stdenv,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "termux-elf-cleaner";
  version = "3.0.1";

  src = fetchFromGitHub {
    owner = "termux";
    repo = "termux-elf-cleaner";
    rev = "v${finalAttrs.version}";
    hash = "sha256-a8vkPABhbR2EfUiDRTppRPyI9n+kDsA/YajqsNpQy6g=";
  };

  nativeBuildInputs = [ cmake ];

  cmakeFlags = [ "-DBUILD_TESTING=OFF" ];
  doCheck = false;

  meta = {
    description = "Remove unsupported ELF metadata from Android binaries";
    homepage = "https://github.com/termux/termux-elf-cleaner";
    license = lib.licenses.gpl3Plus;
    mainProgram = "termux-elf-cleaner";
    platforms = lib.platforms.unix;
  };
})

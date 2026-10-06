{
  fetchFromGitHub,
  lib,
  pkgs,
  ...
}:
let
  source = fetchFromGitHub {
    owner = "pschmitt";
    repo = "adb.sh";
    rev = "6b71752c862069af7b6ee15c3da694d35be87e5d";
    hash = "sha256-ey4k1vWK00e+t+y3UQKAtssOV5ezCgcvPhupTH8CzyI=";
  };
in
pkgs.callPackage ./shell-script.nix {
  name = "adb-sh";
  script = "${source}/adb.sh";
  supportTrees = [
    {
      source = "${source}/lib";
      target = "bin/lib";
    }
  ];
  scriptReplacements = [
    {
      from = "#!/usr/bin/env bash";
      to = "#!/data/data/com.termux/files/usr/bin/bash";
    }
  ];
  aptPackages = [
    "android-tools"
    "gawk"
    "iproute2"
    "nmap"
    "perl"
  ];
  description = "Android device control helpers built on adb";
  homepage = "https://github.com/pschmitt/adb.sh";
  license = lib.licenses.mit;
}

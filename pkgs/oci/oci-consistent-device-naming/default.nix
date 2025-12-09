{
  lib,
  stdenv,
  bash,
}:

stdenv.mkDerivation {
  pname = "oci-udev-persistent-naming";
  version = "1.0";

  # These 2 files were extracted from an oci instance:
  # /usr/local/sbin/oci_udev_persistent_naming
  # /etc/udev/rules.d/99-systemoci-persistent-names.rules
  src = ./oci_udev_persistent_naming;
  rules = ./99-systemoci-persistent-names.rules;

  buildInputs = [ bash ];
  phases = [ "installPhase" ];

  installPhase = ''
    install -Dm 755 $src $out/bin/oci_udev_persistent_naming
    patchShebangs $out/bin/oci_udev_persistent_naming

    install -Dm 644 $rules $out/lib/udev/rules.d/99-systemoci-persistent-names.rules
    sed -i "s#/usr/local/sbin/oci_udev_persistent_naming#$out/bin/oci_udev_persistent_naming#g" \
      $out/lib/udev/rules.d/99-systemoci-persistent-names.rules
  '';

  meta = {
    description = "Support for consistent device naming for Oracle Cloud Infrastructure on NixOS";
    license = lib.licenses.upl;
    maintainers = with lib.maintainers; [ pschmitt ];
  };
}

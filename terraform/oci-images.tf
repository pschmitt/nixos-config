data "oci_core_image" "ubuntu-2204-aarch64-202211060" {
  # Canonical-Ubuntu-22.04-aarch64-2022.11.06-0
  image_id = "ocid1.image.oc1.eu-frankfurt-1.aaaaaaaa7xlh7c3l2xtrn53n5ezp2thnac3hgjo6biolfxisk3l4igfl3xba"
}

data "oci_core_image" "ubuntu-2204-minimal-aarch64-202402180" {
  # Canonical-Ubuntu-22.04-Minimal-aarch64-2024.02.18-0
  image_id = "ocid1.image.oc1.eu-frankfurt-1.aaaaaaaag254u4iki5fxm36aq4f7kzg4yi4hf564cuxfq5aj3jngjp6azmhq"
}

# vim: set ft=terraform :

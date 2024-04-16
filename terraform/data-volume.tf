resource "openstack_blockstorage_volume_v3" "data_volume" {
  name        = "roflvolume-01"
  size        = 4096 # GiB
  availability_zone = var.availability_zone
}

resource "openstack_compute_volume_attach_v2" "va_data" {
  instance_id = openstack_compute_instance_v2.nixos_anywhere_vm.id
  volume_id   = openstack_blockstorage_volume_v3.data_volume.id
}

# vim: set ft=terraform

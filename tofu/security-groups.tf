resource "openstack_networking_secgroup_v2" "secgroup_ssh" {
  name        = "allow-ssh"
  description = "Allow SSH traffic"
}

resource "openstack_networking_secgroup_v2" "secgroup_http" {
  name        = "allow-http"
  description = "Allow HTTP(s) traffic"
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_ssh_v4" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.secgroup_ssh.id
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_ssh_v6" {
  direction         = "ingress"
  ethertype         = "IPv6"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "::/0"
  security_group_id = openstack_networking_secgroup_v2.secgroup_ssh.id
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_http_v4" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.secgroup_http.id
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_http_v6" {
  direction         = "ingress"
  ethertype         = "IPv6"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "::/0"
  security_group_id = openstack_networking_secgroup_v2.secgroup_http.id
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_https_v4" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.secgroup_http.id
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_https_v6" {
  direction         = "ingress"
  ethertype         = "IPv6"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "::/0"
  security_group_id = openstack_networking_secgroup_v2.secgroup_http.id
}

# vim: set ft=terraform

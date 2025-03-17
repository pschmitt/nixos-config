resource "openstack_networking_secgroup_v2" "secgroup_ssh" {
  name        = "allow-ssh"
  description = "Allow SSH traffic"
}

resource "openstack_networking_secgroup_v2" "secgroup_http" {
  name        = "allow-http"
  description = "Allow HTTP(s) traffic"
}

resource "openstack_networking_secgroup_v2" "secgroup_email" {
  name        = "allow-email"
  description = "Allow email (imap+smtp) traffic"
}

resource "openstack_networking_secgroup_v2" "secgroup_xmr" {
  name        = "allow-xmr"
  description = "Allow xmr traffic"
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

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_http_alt_v4" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 8080
  port_range_max    = 8080
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.secgroup_http.id
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_http_alt_v6" {
  direction         = "ingress"
  ethertype         = "IPv6"
  protocol          = "tcp"
  port_range_min    = 8080
  port_range_max    = 8080
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

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_https_alt_v4" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 8443
  port_range_max    = 8443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.secgroup_http.id
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_https_alt_v6" {
  direction         = "ingress"
  ethertype         = "IPv6"
  protocol          = "tcp"
  port_range_min    = 8443
  port_range_max    = 8443
  remote_ip_prefix  = "::/0"
  security_group_id = openstack_networking_secgroup_v2.secgroup_http.id
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_imap_v4" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 143
  port_range_max    = 143
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.secgroup_email.id
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_imap_v6" {
  direction         = "ingress"
  ethertype         = "IPv6"
  protocol          = "tcp"
  port_range_min    = 143
  port_range_max    = 143
  remote_ip_prefix  = "::/0"
  security_group_id = openstack_networking_secgroup_v2.secgroup_email.id
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_imaps_v4" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 993
  port_range_max    = 993
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.secgroup_email.id
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_imaps_v6" {
  direction         = "ingress"
  ethertype         = "IPv6"
  protocol          = "tcp"
  port_range_min    = 993
  port_range_max    = 993
  remote_ip_prefix  = "::/0"
  security_group_id = openstack_networking_secgroup_v2.secgroup_email.id
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_smtp_v4" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 25
  port_range_max    = 25
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.secgroup_email.id
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_smtp_v6" {
  direction         = "ingress"
  ethertype         = "IPv6"
  protocol          = "tcp"
  port_range_min    = 25
  port_range_max    = 25
  remote_ip_prefix  = "::/0"
  security_group_id = openstack_networking_secgroup_v2.secgroup_email.id
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_smtps_v4" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 587
  port_range_max    = 587
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.secgroup_email.id
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_smtps_v6" {
  direction         = "ingress"
  ethertype         = "IPv6"
  protocol          = "tcp"
  port_range_min    = 587
  port_range_max    = 587
  remote_ip_prefix  = "::/0"
  security_group_id = openstack_networking_secgroup_v2.secgroup_email.id
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_monerod_v4" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 18080
  port_range_max    = 18089
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.secgroup_xmr.id
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_monerod_v6" {
  direction         = "ingress"
  ethertype         = "IPv6"
  protocol          = "tcp"
  port_range_min    = 18080
  port_range_max    = 18089
  remote_ip_prefix  = "::/0"
  security_group_id = openstack_networking_secgroup_v2.secgroup_xmr.id
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_xmrig_proxy_v4" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 39674
  port_range_max    = 39674
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.secgroup_xmr.id
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_xmrig_proxy_v6" {
  direction         = "ingress"
  ethertype         = "IPv6"
  protocol          = "tcp"
  port_range_min    = 39674
  port_range_max    = 39674
  remote_ip_prefix  = "::/0"
  security_group_id = openstack_networking_secgroup_v2.secgroup_xmr.id
}

# vim: set ft=terraform

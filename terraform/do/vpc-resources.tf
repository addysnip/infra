resource "digitalocean_vpc" "vpc" {
    name = "${var.vpc_name}"
    region = "${var.region}"
    ip_range = "172.16.0.0/20"
}